# ---------------------------------------------------------------------------
# Drop this target into each project's Makefile (or copy this file as-is).
#
#   make update_skills              # asks the project type, then syncs
#   make update_skills TYPE=kmp     # non-interactive
#
# It clones the central skills repo to a temp dir, runs the sync against THIS
# project, and cleans up. Project-specific skills/rules are preserved.
# ---------------------------------------------------------------------------

# Where the central repo lives. Override once you push it to GitHub:
#   SKILLS_REPO=git@github.com:foshlabs/skills.git
# Or point at a local clone for testing:
#   make update_skills SKILLS_REPO=/Users/adam/Developer/fosh\ labs/skills
SKILLS_REPO ?= git@github.com:foshlabs/skills.git
SKILLS_REF  ?= main
TYPE        ?=

.PHONY: update_skills
update_skills:
	@tmp="$$(mktemp -d)"; \
	trap 'rm -rf "$$tmp"' EXIT; \
	if [ -d "$(SKILLS_REPO)/.git" ]; then \
		cp -R "$(SKILLS_REPO)/." "$$tmp/"; \
	else \
		git clone --quiet --depth 1 --branch "$(SKILLS_REF)" "$(SKILLS_REPO)" "$$tmp"; \
	fi; \
	bash "$$tmp/scripts/update-skills.sh" --project "$(CURDIR)" $(if $(TYPE),--type $(TYPE),)
