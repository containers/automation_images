Thanks for contributing.  Please take careful note of, and do the following:

1. ***Immediatly*** (as in *right now*) change this to a "draft" type
   pull-request for initial submission.  In the github WebUI, this is
   accomplished by pressing the down-arrow on the "Create Pull Request"
   button.

2. Add a maintainer to the "reviewers" section of the new PR
   If in doubt, add @cevich as the reviewer.  Note that **Assuming
   all automated tests pass, and your PR is ***not*** a "draft", it will
   automatically merge once a single approving github review is submitted**.

3. If the PR does not have any (significant) impact on VM or container-image
   content or production.  Prefix the PR-title with the string `[CI:DOCS]`.
   For example, adding comments or changes which will not require deploying
   new VM or container images into other repositories automation config.

4. Erase this template's text, and describe ***why*** the collective set
   of commits are needed.  Do not simply duplicate the commit messages here.
