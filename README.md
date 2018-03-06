# Helm Release Helper

* Parse "directives" from a values file comments to make common release lifecycle operations easier.
* The values file's name is used as the release name (eg the release name for `nginx-ingress.yaml` is `nginx-ingress`)
* Directives appear at the top of the chart like:
```yaml
# CHART_REPOSITORY=https://kubernetes-charts.storage.googleapis.com
# CHART_NAME=nginx-ingress
# CHART_VERSION=0.9.5
# RELEASE_NAMESPACE=kube-system

controller:
  name: controller
  image:
...
```

## Install
```
$ helm plugin install https://github.com/ceason/helm-release-helper
```

## Usage
### Init
"Initialize" a new release by prepending chart location and version information to the content of `helm inspect values`
```
helm release-helper inspect [chartish] > new-release-name.yaml
```
where `[chartish]` is a repository chart reference (eg `stable/nginx-ingress`)


### Diff
Perform a [`helm diff`](https://github.com/databus23/helm-diff) between the specified file and its associated release
```
helm release-helper diff [release-values.yaml]
```

### Apply
Perform a `helm upgrade --install` on the specified release file
```
helm release-helper apply [release-values.yaml]
```

