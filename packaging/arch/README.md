# Arch packaging

Build and install straight from a repo checkout:

```
cd packaging/arch
makepkg -si
```

## Publishing to the AUR

1. Tag a release (`vX.Y.Z`) in the GitHub repo.
2. Replace `sha256sums=('SKIP')` with the real tarball hash:
   `makepkg -g` prints it.
3. Generate `.SRCINFO`: `makepkg --printsrcinfo > .SRCINFO`.
4. Push `PKGBUILD`, `tas2781-force-fwload.install`, and `.SRCINFO` to
   `ssh://aur@aur.archlinux.org/tas2781-force-fwload.git`.
