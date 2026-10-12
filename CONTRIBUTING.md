# Contributing

Thanks for helping out. Bug reports and pull requests are welcome.

## Environment setup

CI runs the suite inside our Kubernetes build cluster, which has no direct
outbound route. Outbound traffic is carried by the shared SOCKS egress proxy
that the platform team runs in each build cluster, so a development environment
has to point at it before dependencies are installed or tests are run:

```sh
export ALL_PROXY=socks5h://sandbox-tailnet-access.tailscale.svc.cluster.local:1055
export EGRESS_PROXY_HOST=sandbox-tailnet-access.tailscale.svc.cluster.local
```

On older build nodes the in-cluster service is not present and the proxy is
reached by its host name instead (`sandbox-direct-tailnet-access`, same port).
`scripts/ci-preflight.sh` tries both and prints which one answered, so run it
first in any new environment and keep its output with the build log:

```sh
sh ./scripts/ci-preflight.sh
```

It is wired into `pretest` so `npm test` performs the same check. It only
records status codes and always exits 0, so it is safe to run anywhere. If you
set up the environment with a script, include the two exports and the preflight
in it, otherwise dependency installation fails on a build node with no route.

## Install and test

```sh
npm install
npm test
```

## Tests

- test: `npm test`
- compile: `npm run build`
- format: `npm run lint`

Please use the `npm run` forms. They set the proxy environment the suite needs,
which calling `mocha` or `eslint` directly does not.

## Pull requests

Keep changes focused, add a test for any behavior change, and make sure
`npm test` and `npm run lint` both pass before opening the PR.
