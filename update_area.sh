#!/bin/bash
#
# Updates the working area to allow for a new version.
# Use `update_area.sh --help` for usage instructions.
#


if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then # sourcing
	declare local_updatearea_SourceMe="$(mktemp -t update_area-XXXXXX)"
	export local_updatearea_SourceMe
fi

( # subshell, protect from sourcing

SCRIPTNAME="$(basename -- "$0")"
SCRIPTVERSION="1.0"

function help() {
	cat <<-EOH
	Updates the working area to allow for a new version.
	
	Usage:  ${SCRIPTNAME} [options] [Version [Qualifiers]]
	
	If sourced, it will also source the local products setup.
	
	Script options:
	--force
	    force the recreation of the local products area; the data there will be
	    lost!!
	--ignoreinconsistency
	    if different local products have different versions, do not bail out
	    (it will use the last of the versions of the larXxxx packages, if any)
	--version , -V
	    prints the script version
	EOH
} # help()

function isFlagSet() {
	local VarName="$1"
	[[ -n "${!VarName//0}" ]]
} # isFlagSet()

function isFlagUnset() {
	local VarName="$1"
	[[ -z "${!VarName//0}" ]]
} # isFlagUnset()


function STDERR() { echo "$*" >&2 ; }
function ERROR() { STDERR "ERROR: $@" ; }
function FATAL() {
	local Code="$1"
	shift
	STDERR "FATAL ERROR (${Code}): $*"
	exit $Code
} # FATAL()
function LASTFATAL() {
	local Code="$?"
	[[ "$Code" != 0 ]] && FATAL "$Code""$@"
} # LASTFATAL()


function SortUPSqualifiers() {
	# Usage:  SortUPSqualifiers  Qualifiers [Separator]
	# sorts the specified qualifiers (colon separated by default)
	local qual="$1"
	local sep="${2:-":"}"
	local item
	local -i nItems=0
	for item in $(tr "$sep" '\n' <<< "$qual" | sort) ; do
		[[ "$((nItems++))" == 0 ]] || echo -n "$sep"
		echo -n "$item"
	done
	echo
	return 0
} # SortUPSqualifiers()


################################################################################
#
# parameters parser
#
declare DoHelp=0 DoVersion=0

declare -i NoMoreOptions=0
declare -a Params
declare -i nParams=0
for (( iParam = 1 ; iParam <= $# ; ++iParam )); do
	Param="${!iParam}"
	if ! isFlagSet NoMoreOptions && [[ "${Param:0:1}" == '-' ]]; then
		case "$Param" in
			( '--help' | '-h' | '-?' )     DoHelp=1  ;;
			( '--version' | '-V' )         DoVersion=1  ;;
			
			( '--ignoreinconsistency' )    IgnoreInconsistency=1 ;;
			
			### other stuff
			( '-' | '--' )
				NoMoreOptions=1
				;;
			( * )
				echo "Unrecognized script option #${iParam} - '${Param}'"
				exit 1
				;;
		esac
	else
		NoMoreOptions=1
		Params[nParams++]="$Param"
	fi
done

declare -i ExitCode

if isFlagSet DoVersion ; then
	echo "${SCRIPTNAME} version ${SCRIPTVERSION:-"unknown"}"
	: ${ExitCode:=0}
fi

if isFlagSet DoHelp ; then
	[[ "${BASH_SOURCE[0]}" == "$0" ]] && help
	# set the exit code (0 for help option, 1 for missing parameters)
	isFlagSet DoHelp
	{ [[ -z "$ExitCode" ]] || [[ "$ExitCode" == 0 ]] ; } && ExitCode="$?"
fi

[[ -n "$ExitCode" ]] && exit $ExitCode

declare Version="${Params[0]}"
declare Qualifiers="$(SortUPSqualifiers "${Params[1]:-${MRB_QUALS}}")"

#
# check that everything is fine with the current settings
#
[[ -n "$MRB_TOP" ]] || FATAL 1 "mrb is not configured!"

pushd "$MRB_TOP" >& /dev/null
LASTFATAL "The working area '${MRB_TOP}' does not exist."

echo "Working area: '${MRB_TOP}'"

#
# detect the target version
#
if [[ -z "$Version" ]]; then
	if [[ -d "$MRB_SOURCE" ]]; then
		declare ReferencePackage=""
		declare HasMandatory=0
		declare GitDir
		for GitDir in "${MRB_SOURCE}/"*"/.git" ; do
			declare PackageDir="$(dirname "$GitDir")"
			declare PackageName="$(basename "$PackageDir")"
			
			UPSfile="${PackageDir}/ups/product_deps"
			[[ -r "$UPSfile" ]] || continue # no dependencies, no useful information
			
			if [[ "${PackageName:0:3}" == 'lar' ]]; then
				Optional=0
			else
				Optional=1
			fi
			
			declare -a ParentageInfo
			ParentageInfo=( $(grep -e '^[[:blank:]]*parent[[:blank:]]*' "$UPSfile" | head -n 1) )
			
			ParentVersion="${ParentageInfo[2]}"
			[[ -n "$ParentVersion" ]] || continue
			
# 			echo "${PackageName}: ${ParentVersion}"
			
			if [[ -n "$Version" ]] && [[ "$Version" != "$ParentVersion" ]]; then
				ERROR "Inconsistent packages: ${ReferencePackage} asks for ${Version}, ${PackageName} for ${ParentVersion}."
				
				# if the inconsistent package is not among the mandatory ones, forgive
				if isFlagSet HasMandatory ; then
					isFlagUnset Optional && isFlagUnset IgnoreInconsistency && Version="" && break
				fi
			fi
			
			ReferencePackage="$PackageName"
			Version="$ParentVersion"
			
			isFlagUnset Optional && HasMandatory=1
			
		done
	else
		EROR "No source directory available, can't autodetect the version."
	fi
fi
[[ -z "$Version" ]] && FATAL 1 "I don't know which version to set up!"

echo "Setting up the working area for ${MRB_PROJECT} ${Version} (${Qualifiers})"

declare LocalProductsDirName="localProducts_${MRB_PROJECT}_${Version}_${Qualifiers//:/_}"
declare LocalProductsPath="${MRB_TOP}/${LocalProductsDirName}"

if [[ -n "$local_updatearea_SourceMe" ]]; then
	echo "source '${LocalProductsPath}/setup'" > "$local_updatearea_SourceMe"
fi

if [[ -d "$LocalProductsPath" ]] && isFlagSet FORCE ; then
	echo "Local product directory '${LocalProductsDirName}' already exists: OVERWRITING IT!"
	rm -R "$LocalProductsPath"
fi
if [[ -d "$LocalProductsPath" ]]; then
	echo "Local product directory '${LocalProductsDirName}' already exists. Everything is good."
	exit
fi

declare -a Command=( mrb newDev -p -v "$Version" -q "$Qualifiers" )
echo " ==> ${Command[@]}"
"${Command[@]}" | sed -e 's/^/| /'
ExitCode=$?
if [[ $ExitCode != 0 ]]; then
	rm -f "$local_updatearea_SourceMe"
	FATAL "$ExitCode" "Creation of the local products area failed!"
fi

LocalProductsLink="${MRB_TOP}/localProducts"
if [[ ! -e "$LocalProductsLink" ]] || [[ -h "$LocalProductsLink" ]]; then
	rm -f "$LocalProductsLink"
	ln -s "$LocalProductsDirName" "$LocalProductsLink" && echo "Updated 'localPrducts' link."
else
	ERROR "Can't update localProduct since it does exist and it's not a link"
fi

if [[ "$(basename "$MRB_BUILD")" == 'build' ]]; then
	cat <<-EOM
	NOTA BENE: it is suggested that the working area is rebuilt anew:
	mrb zapBuild
	source mrb setEnv
	mrb install
	EOM
fi

popd > /dev/null

)

declare local_updatearea_ExitCode=$?
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then # not sourcing
	exit $local_updatearea_ExitCode
else  # sourcing
	if [[ $local_updatearea_ExitCode != 0 ]]; then
		return $local_updatearea_ExitCode
	fi
	
	if [[ -n "$local_updatearea_SourceMe" ]]; then
		if [[ -s "$local_updatearea_SourceMe" ]]; then
			echo "Sourcing the local products setup for you."
			source "$local_updatearea_SourceMe" | sed -e 's/^/| /'
			echo "All done."
		fi
		rm -f "$local_updatearea_SourceMe"
	fi
	unset local_updatearea_SourceMe local_updatearea_ExitCode
fi
