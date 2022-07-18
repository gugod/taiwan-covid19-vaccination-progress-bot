# Test

```
docker build . --tag bot
docker run bot ./bin/tweet.pl
```

# Production

Docker image of latest "release" branch is at here:

https://hub.docker.com/repository/docker/gugod/taiwan-covid19-vaccination-progress-bot

Runs in a k8s cluster:

```
kubectl -apply f ./k8s/
```
