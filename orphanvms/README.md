A container image to help identify possibly orphaned
VM instances. Deliberately avoids producing any output
if no instances are identified.

* `GCPPROJECTS` - Whitespace separated Project IDs to check.
* `GCPJSON` - Contents of the service-account JSON key file. N/B: Must have
  'Compute Read' role for all listed `$GCPPROJECTS`.
* `GCPNAME` - Complete Name (fake e-mail address) of the service account.

Example build (from repository root):

```bash
make orphanvms IMG_SFX=example
```
