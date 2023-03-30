# Tools to manage IO Coop ganeti cluster

## Deployment

To deploy these tools to the live ganeti cluster use Ansible

```
ansible-playbook site.yml --limit ganeti -t ganeti
```

[Section of ansible code which does the deploy](https://github.com/iocoop/configs/blob/2311664e69e46b0222a2bab9ded88d0190c88bac/ansible/roles/ganeti/tasks/main.yml#L38-L41)

To add a new guest OS, one that is newer than the current version of Ubuntu running
on our ganeti hosts, you may need to create a new debootstrap script by running a command like
this on all of the nodes

```shell
ln -sv gutsy /usr/share/debootstrap/scripts/jammy
```
