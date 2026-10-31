# Standard tag contract: lifetime, owner, project, created.
# Hold is `keep` so the nightly sweep does not delete this appliance
# while replication and the video are unfinished. Set this back to `1d`
# in the same change as teardown. The sweep deletes only groups tagged 1d.
# created is a timestamp, so each resource ignores later changes to it.

locals {
  created = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())

  tags = merge(var.tags, {
    lifetime = "keep"
    created  = local.created
  })
}
