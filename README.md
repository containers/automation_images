# README.md

This repository holds the configuration for automation-related VM and
container images.  CI/CD automation in this repo. revolves around
producing new images. It does only very minimal testing of suitability
for their use in the automation of the other *containers* org. repos.

# Contributing

1. Thanks!
2. This repo. follows the [fork & pull
   model](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/creating-a-pull-request-from-a-fork)
3. All required automated tests must pass on a pull-request before it may be merged.
4. ***IMPORTANT***: Automatic pull-requests merging is enabled on this repository!
   Pull requests will be merged if they pass all automated tests and are not marked
   as being a draft or work-in-progress.
5. Pull requests not yet ready for review, must be marked as "draft".
   This can be accomplished either:

   * When a pull-request is first submitted via the Github WebUI. Click
     the drop-down menu next to the green 'Create pull request' button.
     Select the value 'Create draft pull request'.  Click the button.
     changing the green submit button value (dropdown).
   * At any time, by clicking the "convert to draft" link located
     in the upper-right of the pull-request page, under 'Reviewers'.

6. All pull requests must be kept up to date with the base branch.
   The [Mergify bot can help with
   this.](https://doc.mergify.io/commands.html#commands)
5. Strict-merging is enabled to guarantee the tip of the base branch has
   always been checked by automation.
