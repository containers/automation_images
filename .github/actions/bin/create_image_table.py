#!/usr/bin/env python3

"""Parse $GITHUB_WORKSPACE/built_images.json into MD table in $GITHUB_ENV."""

# Note: This script is exclusively intended to be used by the
# pr_image_id.yml github-actions workflow.  Any use outside that
# context is unlikely to function as intended.

import json
import os
import sys


def msg(msg, newline=True):
    """Print msg to stderr with optional newline."""
    nl = ''
    if newline:
        nl = '\n'
    sys.stderr.write(f"{msg}{nl}")
    sys.stderr.flush()


def stage_sort(item):
    """Return sorting-key for build-image-json item."""
    if item["stage"] == "import":
        return str("0010"+item["name"])
    elif item["stage"] == "base":
        return str("0020"+item["name"])
    elif item["stage"] == "cache":
        return str("0030"+item["name"])
    else:
        return str("0100"+item["name"])


if "GITHUB_ENV" not in os.environ:
    raise KeyError("Error: $GITHUB_ENV is undefined.")

cirrus_ci_build_id = None
github_workspace = os.environ.get("GITHUB_WORKSPACE", ".")

# File written by a previous workflow step
with open(f"{github_workspace}/built_images.json") as bij:
  msg(f"Reading image build data from {bij.name}:")
  data = []
  for build in json.load(bij):  # list of build data maps
    stage = build.get("stage", False)
    name = build.get("name", False)
    sfx = build.get("sfx", False)
    task = build.get("task", False)
    if bool(stage) and bool(name) and bool(sfx) and bool(task):
        image_suffix = f'{stage[0]}{sfx}'
        data.append(dict(stage=stage, name=name,
                         image_suffix=image_suffix, task=task))
        if cirrus_ci_build_id is None:
            cirrus_ci_build_id = sfx
        msg(f"Including '{stage}' stage build '{name}' for task '{task}'.")
    else:
        msg(f"Skipping  '{stage}' stage build '{name}' for task '{task}'.")

url = 'https://cirrus-ci.com/task'
lines = []
data.sort(key=stage_sort)
for item in data:
  image_suffix = item["image_suffix"]
  # Base-images should never actually be used, but it may be helpful
  # to have them in the list in case some debugging is needed.
  if item["stage"] != "cache":
    image_suffix = "do-not-use"
  lines.append('|*{0}*|[{1}]({2})|`{3}`|\n'.format(item['stage'],
    item['name'], '{0}/{1}'.format(url, item['task']), image_suffix))


# This is the mechanism required to set an multi-line env. var.
# value to be consumed by future workflow steps.
with open(os.environ["GITHUB_ENV"], "a") as ghenv, \
     open(f'{github_workspace}/images.md', "w") as mdfile, \
     open(f'{github_workspace}/images.json', "w") as images_json:

    env_header = ("IMAGE_TABLE<<EOF\n")
    header = (f"[Cirrus CI build](https://cirrus-ci.com/build/{cirrus_ci_build_id})"
               " successful. [Found built image names and"
              f' IDs](https://github.com/{os.environ["GITHUB_REPOSITORY"]}'
              f'/actions/runs/{os.environ["GITHUB_RUN_ID"]}):\n'
               "\n")
    c_head = ("|*Stage*|**Image Name**|`IMAGE_SUFFIX`|\n"
              "|---|---|---|\n")
    # Different output destinations get slightly different content
    for dst in [ghenv, mdfile, sys.stderr]:
        if dst == ghenv:
            dst.write(env_header)
        if dst != sys.stderr:
            dst.write(header)
        dst.write(c_head)
        dst.writelines(lines)
        if dst == ghenv:
            dst.write("EOF\n\n")

    json.dump(data, images_json, indent=4, sort_keys=True)
    msg(f"Wrote github env file '{ghenv.name}', md-file '{mdfile.name}',"
        f" and json-file '{images_json.name}'")
