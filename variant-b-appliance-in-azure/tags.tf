# Standard tag contract: lifetime, owner, project, created.
# Default is `1d` so the nightly sweep can delete this appliance. Use
# `keep` only for an overnight hold, then set this back to `1d` in the
# same change as teardown. The sweep deletes only groups tagged 1d.
# created is a timestamp, so each resource ignores later changes to it.

locals {
  created = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())

  tags = merge(var.tags, {
    lifetime = "1d"
    created  = local.created
  })
}
