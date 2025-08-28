#!/usr/bin/env bash
set -eu

NIXPKGS_LIB_MODULES=(
	misc/meta misc/assertions
	misc/passthru
	misc/lib
	misc/ids
)
LIBFILES=()
for mod in "${NIXPKGS_LIB_MODULES[@]}"; do
	LIBFILES+=(nixos/modules/$mod.nix)
done

export GIT_{COMMITTER,AUTHOR}_EMAIL=ghost@konpaku.2hu
export GIT_{COMMITTER,AUTHOR}_NAME=ghost

NIXPKGS_BRANCH=${NIXPKGS_BRANCH-master}
NIXPKGS_LIB_GENERATE=${NIXPKGS_LIB_GENERATE-$NIXPKGS_LIB/generate}
export NIXPKGS_LIB_GENERATE_NIXPKGS=$NIXPKGS_LIB_GENERATE/nixpkgs
git-nixpkgs() {
	command git -C "$NIXPKGS_LIB_GENERATE_NIXPKGS" "$@"
}

git-lib() {
	command git -C "$NIXPKGS_LIB_MASTER" "$@"
}

git() {
	command git -C "$NIXPKGS_LIB" "$@"
}

generate-nixpkgs-update() {
	git submodule update --init --remote $NIXPKGS_LIB_GENERATE_NIXPKGS
	git-nixpkgs checkout --detach origin/$NIXPKGS_BRANCH

	LAST_LIB_COMMIT=$(git-nixpkgs log -n1 --pretty=format:%H -- lib/ "${LIBFILES[@]}")
	echo "Resetting generate/nixpkgs to $LAST_LIB_COMMIT" >&2
	git-nixpkgs show -s --oneline $LAST_LIB_COMMIT >&2
}

generate-nixpkgs-checkout() {
	NIXPKGS_LIB_BRANCH=$(cat $NIXPKGS_LIB_GENERATE_NIXPKGS/.version)
	NIXPKGS_LIB_BRANCH=lib-$NIXPKGS_LIB_BRANCH
	NIXPKGS_LIB_MASTER=$NIXPKGS_LIB_GENERATE/$NIXPKGS_LIB_BRANCH
	git worktree remove $NIXPKGS_LIB_MASTER 2>/dev/null || true

	if [[ -v LAST_LIB_COMMIT ]]; then
		git-nixpkgs checkout -B nixpkgs-$NIXPKGS_LIB_BRANCH $LAST_LIB_COMMIT
	else
		git-nixpkgs checkout nixpkgs-$NIXPKGS_LIB_BRANCH
	fi

	for libbranch in nixpkgs-$NIXPKGS_LIB_BRANCH $NIXPKGS_LIB_BRANCH; do
		git branch -t $libbranch origin/$libbranch 2>/dev/null || true
	done
}

generate-is-ci() {
	[[ ${CI_PLATFORM-} = gh-actions ]] && [[ ${GITHUB_REF-} = refs/heads/generate || ${GITHUB_EVENT_NAME-} = schedule ]] ||
		return 1
}

generate-is-dirty() {
	[[ -n $(git status --porcelain --untracked-files=no) ]] ||
		return 1
}

generate-is-nixpkgs-dirty() {
	if [[ ! -v LIB_CHANGES ]]; then
		LIB_CHANGES="$(git status --porcelain generate/nixpkgs)"
	fi
	[[ -n $LIB_CHANGES ]] ||
		return 1
}

generate-assert-clean() {
	if generate-is-dirty; then
		echo "git tree is dirty, aborting" >&2
		exit 1
	fi
}

generate-filter() {
	FILTER_ARGS=(
		--force
		--target $NIXPKGS_LIB
		--partial --refs nixpkgs-$NIXPKGS_LIB_BRANCH
		--prune-empty always --no-ff
		--path '.version' --path 'lib/.version'
		--path-glob 'lib/*.nix'
		--path-glob 'lib/deprecated/*.nix'
		--path-glob 'lib/fileset/*.nix'
		--path-glob 'lib/network/*.nix'
		--path-glob 'lib/path/*.nix'
		--path-glob 'lib/systems/*.nix'
		"$@"
	)
	for mod in "${LIBFILES[@]}"; do
		FILTER_ARGS+=(--path "$mod")
	done
	git-nixpkgs filter-repo "${FILTER_ARGS[@]}"
}

generate-filter-cleanup() {
	# partial disables post-filter gc, so do it manually...
	#git reflog expire --expire=now --all
	git gc --prune=now
}

generate-commit() {
	git add generate/nixpkgs
	git commit -m "submodule update"
}

generate-push() {
	git push origin nixpkgs-${NIXPKGS_LIB_BRANCH}:nixpkgs-$NIXPKGS_LIB_BRANCH
	git push origin generate
	git-lib push origin ${NIXPKGS_LIB_BRANCH}:$NIXPKGS_LIB_BRANCH
}

generate-lib-init() {
	if [[ ! -v NIXPKGS_LIB_MASTER ]]; then
		generate-nixpkgs-checkout
	fi
	if [[ -v NIXPKGS_LIB_FRESH ]]; then
		return
	fi
	NIXPKGS_LIB_FRESH=
	if ! git rev-parse --verify origin/$NIXPKGS_LIB_BRANCH 2> /dev/null; then
		NIXPKGS_LIB_FRESH=1
	fi
}

generate-is-lib-fresh() {
	[[ -n $NIXPKGS_LIB_FRESH ]] ||
		return 1
}

generate-lib-checkout() {
	generate-lib-init
	if [[ ! -d $NIXPKGS_LIB_MASTER ]]; then
		if generate-is-lib-fresh; then
			git worktree add $NIXPKGS_LIB_MASTER -b $NIXPKGS_LIB_BRANCH generate
		else
			git worktree add $NIXPKGS_LIB_MASTER $NIXPKGS_LIB_BRANCH
		fi
	else
		if generate-is-lib-fresh; then
			git-lib checkout -B $NIXPKGS_LIB_BRANCH generate
		else
			git-lib checkout $NIXPKGS_LIB_BRANCH
		fi
	fi
}

generate-lib-merge() {
	generate-lib-init
	MERGE_ARGS=(--no-ff --no-edit)
	if generate-is-lib-fresh; then
		MERGE_ARGS+=(--allow-unrelated-histories)
	else
		git-lib merge "${MERGE_ARGS[@]}" generate
	fi
	if generate-is-nixpkgs-dirty || generate-is-lib-fresh; then
		git-lib merge "${MERGE_ARGS[@]}" nixpkgs-$NIXPKGS_LIB_BRANCH
	fi
	nix flake check $NIXPKGS_LIB_MASTER
}

main() {
	generate-assert-clean
	if generate-is-ci; then
		generate-nixpkgs-update
	fi
	generate-nixpkgs-checkout

	if generate-is-nixpkgs-dirty; then
		generate-filter
		generate-filter-cleanup
	else
		echo "no changes detected upstream" >&2
	fi

	if generate-is-ci; then
		if generate-is-nixpkgs-dirty; then
			generate-commit
		fi
		generate-lib-checkout
		generate-lib-merge
		if generate-is-nixpkgs-dirty; then
			generate-push
		fi
	fi
}

do-update() {
	generate-nixpkgs-update
}

do-filter() {
	generate-nixpkgs-checkout

	generate-filter
	generate-filter-cleanup
}

do-lib() {
	generate-assert-clean
	generate-nixpkgs-checkout

	generate-lib-checkout
	generate-lib-merge
}

do-push() {
	generate-nixpkgs-checkout

	generate-push
}

RUN_CMD=main
if [[ $# -gt 0 ]]; then
	RUN_CMD=$1
	shift
fi
"$RUN_CMD" "$@"
