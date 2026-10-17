# hindsight

[Hindsight](https://github.com/vectorize-io/hindsight) agent memory as the estate
runs it: upstream's api, control plane and
[text-embeddings-inference](https://github.com/huggingface/text-embeddings-inference)
images, changed only so that they run under the estate's restricted posture.
deploy-kit delivers them as the Project `hindsight`.

## What the images change

Each image runs as uid 1000 with a read-only root filesystem and every
capability dropped. Only `/tmp` is writable, plus TEI's model cache at `/data`.

- `api/` is the api and the worker in one image. `hindsight-start` picks one
  of them by `HINDSIGHT_ROLE`, since upstream starts the worker only through a
  command override. It also builds `HINDSIGHT_API_DATABASE_URL` and both TEI
  URLs from separate host, port and credential variables, because the estate
  delivers each of those as its own value.
- `control-plane/` serves the control plane on its own. Upstream's
  `start-all.sh` first checks for an embedded database under `$HOME`, which a
  read-only root doesn't have. It builds the api's URL from its host and port.
- `tei/` is TEI on CPU with a numeric user. Every TEI flag has an environment
  variable, so the Project sets the model in its env files.

## Running it

`deploy/hindsight.project.yml` and `deploy/env/` declare the Project:
- the api and the worker on the platform's Postgres (`hindsight_db`);
- the control plane;
- the bge-m3 embedding model and the mmarco reranker, both on CPU until
  deploy-kit renders a GPU request (JorisJonkers-dev/deploy-kit#398).

Each release builds the images and publishes the Intent Fragment that the
estate composes.

`scripts/smoke-test.sh` starts every image restricted beside Postgres with
pgvector, with small TEI models, and waits until each one serves. CI runs it
on every change.

## Licence

MIT, as Hindsight is: see [LICENSE](LICENSE).
