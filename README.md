# Tools to manage IO Coop ganeti cluster

## Deployment

To deploy these tools to the live ganeti cluster use Ansible

```
ansible-playbook site.yml --limit ganeti -t ganeti
```

[Section of ansible code which does the deploy](https://github.com/iocoop/configs/blob/2311664e69e46b0222a2bab9ded88d0190c88bac/ansible/roles/ganeti/tasks/main.yml#L38-L41)
