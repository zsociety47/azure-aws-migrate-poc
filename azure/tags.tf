# Standard tag contract: lifetime, owner, project, created.
# Default is `1d` so the nightly sweep can delete the groups. Use `keep`
# only for an overnight hold, then set this back to `1d` in the same
# change as teardown. The sweep deletes only Azure groups tagged 1d.
# created is a timestamp, so each resource ignores later changes to it.
# Otherwise every plan would try to rewrite the tag.

locals {
  created = formatdate("YYYY-MM-DD'T'hh:mm:ss'Z'", timestamp())

  tags = merge(var.tags, {
    lifetime = "1d"
    created  = local.created
  })
}
