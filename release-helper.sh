#!/usr/bin/env bash
[ "$HELM_DEBUG" = "1" ] && set -x
set -euo pipefail
err_report() { echo "errexit on line $(caller)" >&2; }
trap err_report ERR

export HELM_HOST=${TILLER_HOST}

_extract-var(){
	local values_file=$1
	local var=$2
	local value=$(grep "^# $var=" "$values_file"|cut -d'=' -f2-|head -1)
	source <(echo $var="$value")
}

_extract-vars(){
	VALUES_FILE=$1
	RELEASE_NAME=${VALUES_FILE%.*}
	local vars=(
		RELEASE_NAMESPACE
		CHART_REPOSITORY
		CHART_NAME
		CHART_VERSION
		HELM_EXTRA_ARGS
	)
	for var in ${vars[@]}; do
		_extract-var $VALUES_FILE $var
	done
	if [ -e "${CHART_REPOSITORY}/Chart.yaml" ]; then
		CHART_URI="$CHART_REPOSITORY"
	else
		CHART_URI="$CHART_REPOSITORY/$CHART_NAME-$CHART_VERSION.tgz"
	fi
}

_chartish2uri(){
	local chartish="${1:-$(cat)}"
	local rgx="[a-z0-9]+://.*"
	if [[ "$chartish" =~ $rgx ]]; then
		# return things that look like URLs w/o modification
		printf '%s' "$chartish"
		return 0
	fi
	local rgx="\w+/\w+"
	if [[ "$chartish" =~ $rgx ]]; then
		# this looks like a chart in a repository, so try to look up the repo's URI
		local repo_name=$(echo "$chartish"|cut -d'/' -f1)
		"$HELM_BIN" repo list|grep "^$repo_name[^\w]"|head -1|cut -f2
		return 0
	fi
	(>&2 echo "Could not match the provided 'chartish' as either a URL or chart repository reference: $chartish")
	return 1
}

diff(){
	_extract-vars $1
	"$HELM_BIN" diff \
	  --values "$VALUES_FILE" \
	  ${HELM_EXTRA_ARGS:=""} \
	  $RELEASE_NAME $CHART_URI
}


apply(){
	_extract-vars $1
	shift

	if "$HELM_BIN" get "$RELEASE_NAME" > /dev/null; then
		# produce a diff if the release already exists
		"$HELM_BIN" diff \
		  --values "$VALUES_FILE" \
		  ${HELM_EXTRA_ARGS:=""} \
		  $RELEASE_NAME $CHART_URI
		if [ -t 1 ]; then
			# If prompt is interactive, ask for confirmation
			read -p "Are you sure? [Y/n]: " -r
			if [[ ! $REPLY =~ ^[Yy]$ ]]
			then
				echo "Aborting operation"
				exit 0
			fi
		fi
	fi

	"$HELM_BIN" upgrade $RELEASE_NAME $CHART_URI \
	  --install \
	  --wait \
	  --values=$VALUES_FILE \
	  --namespace=$RELEASE_NAMESPACE \
	  ${HELM_EXTRA_ARGS:=""} \
	  "$@"
}

template(){
	_extract-vars $1
	shift

	local tmp_dir=$(mktemp -d -t helmchart-XXXXXX)
	local fetch_dir=$tmp_dir/fetch
	local template_dir=$tmp_dir/template

	"$HELM_BIN" fetch $CHART_URI --untar --untardir=$fetch_dir

	# need to find the dir with Chart.yaml in it (urgh)
	local chart_dir=$(dirname $(find $fetch_dir -maxdepth 2 -type f -name Chart.yaml|head -1))

	mkdir -p "$template_dir"

	"$HELM_BIN" template $chart_dir \
	  --name $RELEASE_NAME \
	  --namespace=$RELEASE_NAMESPACE \
	  --output-dir=$template_dir \
	  --values=$VALUES_FILE

	mkdir -p $RELEASE_NAME

	# find where the manifests were rendered out to (must be a better way??)
#	local manifest_dir=$(find "$template_dir" -type d -name templates|head -1)
#	cp $manifest_dir/* $RELEASE_NAME/.

#	for manifest_dir in $(find "$template_dir" -type d -name templates); do
#		cp $manifest_dir/*.yaml $RELEASE_NAME/.
#	done

	for f in $(find "$template_dir" -type f -name \*.yaml); do
		local tgt_name=$(kubectl apply --dry-run -f "$f" -ogo-template='{{.metadata.name}}-{{.kind}}.yaml')
		local tgt_file="$RELEASE_NAME/${tgt_name,,}"
		if [ -e "$tgt_file" ]; then
			echo "Skipping, file exists: $tgt_file"
		else
			echo "Writing: $tgt_file"
			cp "$f" "$tgt_file"
		fi
	done

	rm -rf $tmp_dir
}


init(){
	local chartish repo info name version ns
	chartish="$1"
	repo=$(_chartish2uri "$chartish")
	info=$("$HELM_BIN" inspect chart "$chartish")
	name=$(echo "$info"|grep '^name:'|cut -d' ' -f2)
	version=$(echo "$info"|grep '^version:'|cut -d' ' -f2)
	ns=$(kubectl config get-contexts|grep '^*'|awk '{print $NF}')
	cat << EOF
# CHART_REPOSITORY=$repo
# CHART_NAME=$name
# CHART_VERSION=$version
# RELEASE_NAMESPACE=$ns

$("$HELM_BIN" inspect values "$chartish")
EOF
}

"$@"

