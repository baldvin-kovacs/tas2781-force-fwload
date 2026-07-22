# Arch packaging

Build and install straight from a repo checkout:

```
cd packaging/arch
makepkg -si
```

`makepkg` downloads the release tarball and its detached PGP signature from
GitHub and verifies both the sha256 and the signature. Import the maintainer
key once before building:

```
gpg --keyserver keys.openpgp.org --recv-keys 1C711551878F8E1EC2F47E37F57A7B17F6FFB8C8
```

## Release + AUR update procedure (maintainer notes)

1. Bump `pkgver` here, set `sha256sums` first entry to `SKIP`, update
   CHANGELOG; commit and tag `vX.Y.Z` (tags are GPG-signed automatically).
2. Create and sign the source tarball, upload both as release assets:

   ```
   git archive --format=tar.gz --prefix=tas2781-force-fwload-X.Y.Z/ vX.Y.Z \
       > tas2781-force-fwload-X.Y.Z.tar.gz
   gpg --detach-sign --armor tas2781-force-fwload-X.Y.Z.tar.gz
   gh release create vX.Y.Z tas2781-force-fwload-X.Y.Z.tar.gz{,.asc} ...
   ```

3. Pin the tarball sha256 in this PKGBUILD (`sha256sum <tarball>`; the
   `.asc` entry stays `SKIP`), commit, push.
4. Update the AUR checkout (`ssh://aur@aur.archlinux.org/tas2781-force-fwload.git`):
   copy in `PKGBUILD` + `tas2781-force-fwload.install`, then

   ```
   makepkg --printsrcinfo > .SRCINFO
   git commit -am "vX.Y.Z" && git push
   ```
