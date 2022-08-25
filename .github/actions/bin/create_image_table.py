#!/usr/bin/env python3

"""Parse /tmp/built_images.json into MD table in $IMAGE_TABLE"""

# Note: This script is exclusively intended to be used by the
# pr_image_id.yml github-actions workflow.  Any use outside that
# context is unlikely to function as intended.

import json
import os

if "GITHUB_ENV" not in os.environ:
    raise KeyError("Error: $GITHUB_ENV is undefined.")

cirrus_ci_build_id = ""

# File written by a previous workflow step
with open("/tmp/built_images.json") as bij:
  data = []
  for build in json.load(bij):  # list of build data maps
    stage = build.get("stage",False)
    name = build.get("name",False)
    sfx = build.get("sfx",False)
    task = build.get("task",False)
    if stage and name and sfx:
        image_suffix = f'{stage[0]}{sfx}'
        data.append(dict(stage=stage, name=name,
            image_suffix=image_suffix, task=task))
        if ! len(cirrus_ci_build_id):
            cirrus_ci_build_id = sfx

url='https://cirrus-ci.com/task'
lines=[]
data.sort(key=lambda item: str(item["stage"]+item["name"]))
for item in data:
  lines.append('|*{0}*|[{1}]({2})|`{3}`|\n'.format(item['stage'],
    item['name'], '{0}/{1}'.format(url, item['task']),
    item['image_suffix']))

# This is the mechanism required to set an multi-line env. var.
# value to be consumed by future workflow steps.
with open(os.environ["GITHUB_ENV"], "a") as ghenv:
  ghenv.write(("IMAGE_TABLE<<EOF\n"
              f"[Cirrus CI build](https://cirrus-ci.com/build/{cirrus_ci_build_id})"
               " successful. [Found built image names and"
              f' IDs](https://github.com/{os.environ["GITHUB_REPOSITORY"]}/actions/runs/{os.environ["GITHUB_RUN_ID"]}):\n'
               "\n"
               "|*Stage*|**Image Name**|`IMAGE_SUFFIX`|\n"
               "|---|---|---|\n"))
  ghenv.writelines(lines)
  ghenv.write("EOF\n\n")
