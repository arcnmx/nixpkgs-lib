set -eu

NIXPKGS_LIB_MODULES=(
	misc/meta misc/assertions
	misc/passthru
	misc/lib
	misc/ids
)

export GIT_{COMMITTER,AUTHOR}_EMAIL=ghost@konpaku.2hu
export GIT_{COMMITTER,AUTHOR}_NAME=ghost

export NIXPKGS_LIB_GENERATE_NIXPKGS=$NIXPKGS_LIB_GENERATE/nixpkgs
git-nixpkgs() {
	command git -C $NIXPKGS_LIB_GENERATE_NIXPKGS "$@"
}

git() {
	command git -C $NIXPKGS_LIB "$@"
}

if [[ -n $(git status --porcelain --untracked-files=no) ]]; then
	echo "git tree is dirty, aborting" >&2
	exit 1
fi

git submodule update --init --remote $NIXPKGS_LIB_GENERATE_NIXPKGS
git-nixpkgs checkout --detach origin/master

LIBFILES=()
for mod in "${NIXPKGS_LIB_MODULES[@]}"; do
	LIBFILES+=(nixos/modules/$mod.nix)
done
LAST_LIB_COMMIT=$(git-nixpkgs log -n1 --pretty=format:%H -- lib/ "${LIBFILES[@]}")
echo "Resetting generate/nixpkgs to $LAST_LIB_COMMIT" >&2
git-nixpkgs show -s --oneline $LAST_LIB_COMMIT >&2

git-nixpkgs checkout -B nixpkgs-lib $LAST_LIB_COMMIT

LIB_CHANGES="$(git status --porcelain generate/nixpkgs)"

if [[ -z $LIB_CHANGES ]]; then
	echo "no changes detected upstream" >&2
else
	FILTER_ARGS=(
		--force
		--target $NIXPKGS_LIB
		--partial --refs nixpkgs-lib
		--prune-empty always --no-ff
		--path-glob 'lib/*.nix'
		--path-glob 'lib/systems/*.nix'
		"$@"
	)
	for mod in "${LIBFILES[@]}"; do
		FILTER_ARGS+=(--path "$mod")
	done
	git-nixpkgs filter-repo "${FILTER_ARGS[@]}"

	# partial disables post-filter gc, so do it manually...
	#git reflog expire --expire=now --all
	git gc --prune=now
fi

if [[ ${CI_PLATFORM-} = gh-actions ]] && [[ ${GITHUB_REF-} = refs/heads/generate || ${GITHUB_EVENT_NAME-} = schedule ]]; then
	if [[ -n $LIB_CHANGES ]]; then
		git push origin nixpkgs-lib:nixpkgs-lib

		git add generate/nixpkgs
		git commit -m "submodule update"
		git push origin generate
	fi

	NIXPKGS_LIB_MASTER=$NIXPKGS_LIB_GENERATE/master
	MERGE_ARGS=(--no-ff --no-edit)
	NEW_MASTER=
	if git rev-parse --verify origin/master 2> /dev/null; then
		git worktree add $NIXPKGS_LIB_MASTER master
		git -C $NIXPKGS_LIB_MASTER merge "${MERGE_ARGS[@]}" generate
	else
		git worktree add $NIXPKGS_LIB_MASTER -b master generate
		MERGE_ARGS+=(--allow-unrelated-histories)
		NEW_MASTER=1
	fi
	if [[ -n $LIB_CHANGES || -n $NEW_MASTER ]]; then
		git -C $NIXPKGS_LIB_MASTER merge "${MERGE_ARGS[@]}" origin/nixpkgs-lib
	fi
	nix flake check $NIXPKGS_LIB_MASTER
	git -C $NIXPKGS_LIB_MASTER push origin master
fi
