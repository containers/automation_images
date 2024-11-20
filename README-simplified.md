The README here is waaaaaay too complicated for Ed. So here is a
simplified version of the typical things you need to do.

Super Duper Simplest Case
=========================

This is by far the most common case, and the simplest to understand.
You do this when you want to build VMs with newer package versions than
whatever VMs are currently set up in CI. You really need to
understand this before you get into anything more complicated.
```
$ git checkout -b lets-see-what-happens
$ make IMG_SFX
$ git commit -asm"Let's just see what happens"
```
...and push that as a PR.

If you're lucky, in about an hour you will get an email from `github-actions[bot]`
with a nice table of base and cache images, with links. I strongly encourage you
to try to get Ed's
[cirrus-vm-get-versions](https://github.com/edsantiago/containertools/tree/main/cirrus-vm-get-versions)
script working, because this will give you a very quick easy reliable
list of what packages have changed. You don't need this, but life will be painful
for you without it.

(If you're not lucky, the build will break. There are infinite ways for
this to happen, so you're on your own here. Ask for help! This is a great
team, and one or more people may quickly realize the problem.)

Once you have new VMs built, **test in an actual project**! Usually podman
and buildah, but you may want the varks too:
```
$ cd ~/src/github/containers/podman     ! or wherever
$ git checkout -b test-new-vms
$ vim .cirrus.yml
[ search for "c202", and replace with your new IMG_SFX.]
[ Don't forget the leading "c"! ]
$ git commit -as
[ Please include a link to the automation_images PR! ]
```
Push this PR and see what happens. If you're very lucky, it will
pass on this and other repos. Get your podman/buildah/vark PRs
reviewed and merged, and then review-merge the automation_images one.

Pushing (har har) Your Luck
---------------------------

Feel lucky? Tag this VM build, so `dependabot` will create PRs
on all the myriad container repos:
```
$ git tag $(<IMG_SFX)
$ git push --no-verify upstream $(<IMG_SFX)
```

Within a few hours you'll see a ton of PRs. It is very likely that
something will go wrong in one or two, and if so, it's impossible to
cover all possibilities. As above, ask for help.

More Complicated Cases
======================

These are the next two most common.

Bumping One Package
-------------------

Quite often we need an emergency bump of only one package that
is not yet stable. Here are examples of the two most typical
cases,
[crun](https://github.com/containers/automation_images/pull/386/files) and
[pasta](https://github.com/containers/automation_images/pull/383/files).
Note the `timebomb` directives. Please use these: the time you save
may be your own, one future day. And please use 2-6 week times.
A timebomb that expires in a year is going to be hard to understand
when it goes off.

Bumping Distros
---------------

Like Fedora 40 to 41. Edit `Makefile`. Change `FEDORA`, `PRIOR_FEDORA`,
and `RAWHIDE`, then proceed with Simple Case.

There is almost zero chance that this will work on the first try.
Sorry, that's just the way it is. See the
[F40 to F41 PR](https://github.com/containers/automation_images/pull/392/files)
for a not-atypical example.


STRONG RECOMMENDATION
=====================

Read [check-imgsfx.sh](check-imgsfx.sh) and follow its instructions. Ed
likes to copy that to `.git/hooks/pre-push`, Chris likes using some
external tool that Ed doesn't trust. Use your judgment.

The reason for this is that you are going to forget to `make IMG_SFX`
one day, and then you're going to `git push --force` an update and walk
away, and come back to a failed run because `IMG_SFX` must always
always always be brand new.


Weak Recommendation
-------------------

Ed likes to fiddle with `IMG_SFX`, zeroing out to the nearest
quarter hour. Absolutely unnecessary, but easier on the eyes
when trying to see which VMs are in use or when comparing
diffs.
