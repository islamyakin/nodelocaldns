# NodeLocal DNSCache
NodeLocal DNSCache in Elastic Kubernetes Service (Amazon EKS) 


#### Instalasi

Download eksctl

Buat Cluster dengan custome DNS. contoh cluster
```eksctl create cluster -f cluster/eksctl/simple-cluster.yaml```

Edit file ```nodelocaldns.yaml```
```
kubedns=`kubectl get svc kube-dns -n kube-system -o jsonpath={.spec.clusterIP}`
domain=cluster.local
localdns=169.254.20.10
```

```
sed -i "s/__PILLAR__LOCAL__DNS__/$localdns/g; s/__PILLAR__DNS__DOMAIN__/$domain/g; s/__PILLAR__DNS__SERVER__/$kubedns/g" nodelocaldns.yaml
```

Simpan konfigurasi
```kubectl apply -f nodelocaldns.yaml```

### Referensi
- https://kubernetes.io/docs/tasks/administer-cluster/nodelocaldns/
- https://github.com/aws/containers-roadmap/issues/303