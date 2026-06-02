# k3s CNPG GCS Backups

Coin-Ops CNPG backups use the CloudNativePG Barman Cloud Plugin. The custom PostgreSQL runtime image is not modified; Barman runs in plugin-managed sidecars.

## Provisioning

1. Run Terraform so the GCS bucket, backup service account, bucket IAM binding, service account key, and generated Ansible metadata are created.
2. Run make k3s-coinops so Ansible installs cert-manager, CNPG, the Barman Cloud Plugin, the GCS credential Secret, the ObjectStore, and the daily ScheduledBackup.
3. Confirm the plugin is available:

    kubectl rollout status deployment/barman-cloud -n cnpg-system

4. Confirm backup resources exist:

    kubectl get objectstore,scheduledbackup,backup -n coinops-data

## Backup Checks

The default schedule is 0 0 2 * * *, which is 02:00 UTC daily in CNPG six-field cron format. The default retention policy is 30d.

Check recent backup status:

    kubectl get backup -n coinops-data
    kubectl describe scheduledbackup coinops-postgres-daily -n coinops-data

Create an on-demand plugin backup when validating a new environment:

    kubectl apply -f - <<YAML
    apiVersion: postgresql.cnpg.io/v1
    kind: Backup
    metadata:
      name: coinops-postgres-manual
      namespace: coinops-data
    spec:
      cluster:
        name: coinops-postgres
      method: plugin
      pluginConfiguration:
        name: barman-cloud.cloudnative-pg.io
    YAML

## Test Namespace Restore

Use a separate namespace for restore drills so production Services and Secrets are not overwritten. Copy or recreate the GCS credentials Secret in the test namespace, then create an ObjectStore pointing at the same destinationPath.

Example skeleton:

    kubectl create namespace coinops-restore-test
    kubectl get secret coinops-cnpg-gcs-backup -n coinops-data -o yaml | sed "s/namespace: coinops-data/namespace: coinops-restore-test/" | kubectl apply -f -

Then apply a restore-only CNPG Cluster in coinops-restore-test using the Barman Cloud Plugin recovery settings and a distinct cluster name such as coinops-postgres-restore. Use kubectl get backup -n coinops-data to choose the backup target, and prefer point-in-time recovery only after confirming WAL archiving has been healthy.

After validation, delete the test namespace:

    kubectl delete namespace coinops-restore-test

## Notes

- Terraform stores the generated service account key in state. The account is bucket-scoped and should not be reused outside CNPG backups.
- The backup bucket has public access prevention and uniform bucket-level access enabled.
- If the CNPG operator is older than 1.26, Ansible fails before applying plugin resources.
