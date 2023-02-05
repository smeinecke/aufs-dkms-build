# aufs-dkms-build/
Build aufs for debian 11 (bullseye) kernel


## Add Repo:
```
apt-get install software-properties-common
apt-add-repository 'deb [arch=amd64] https://smeinecke.github.io/aufs-dkms-build/repo bullseye main'
wget -O ~/dkms.key https://smeinecke.github.io/aufs-dkms-build/public.key
gpg --no-default-keyring --keyring ./dkms_keyring.gpg --import dkms.key
gpg --no-default-keyring --keyring ./dkms_keyring.gpg --export > ./dkms.gpg
mv ./dkms.gpg /etc/apt/trusted.gpg.d/
```