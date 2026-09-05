# Vaporcito

![Vaporcito Logo](back/img/vaporcito-logo.png)

---

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Overview

Vaporcito is a lightweight and user-friendly savegame synchronization tool designed to seamlessly synchronize game progress between multiple computers. Whether you're switching between your gaming rig and laptop or collaborating with friends, Vaporcito ensures your savegames are always up-to-date.

## Repository layout

```text
front/     Web GUI (gui/), desktop shell (desktop/), assets, next-gen-gui
back/      Go module (cmd/, lib/, go.mod, build.go, scripts/ helpers)
scripts/   build.sh + Docker entrypoints
docker/    Dockerfiles and compose
```

## Features

- **Effortless Synchronization**: Vaporcito keeps your savegames in sync without requiring constant user intervention.

- **Security First**: Protecting your game progress is our top priority. Vaporcito employs robust security measures to safeguard your savegame data.

- **Cross-Platform Compatibility**: Run Vaporcito on a variety of platforms, ensuring compatibility with different gaming setups.

- **Minimal User Interaction**: Vaporcito operates in the background, minimizing interruptions to your gaming experience.

## Getting Started

### Build the engine (Go)

```bash
cd back
go run build.go -no-upgrade build
# or:
./scripts/build.sh -no-upgrade build
```

Without a local Go toolchain, build via Docker (from the repo root):

```bash
docker run --rm -v "$PWD":/src -w /src/back \
  -e CGO_ENABLED=0 golang:1.22-bookworm \
  go run build.go -no-upgrade -version v1.0.0-vaporcito build
```

### Docker Compose

```bash
docker compose -f docker/docker-compose.yml up --build -d
```

UI: http://127.0.0.1:8384

### Desktop (Tauri)

See [front/desktop/README.md](front/desktop/README.md).

## Installation

To install Vaporcito on your system, follow the steps outlined in the [Installation Guide](link-to-your-installation-guide).

## Configuration

Customize Vaporcito to suit your preferences using the [Configuration Guide](link-to-your-configuration-guide).

## Contributing

We welcome contributions to improve Vaporcito! Check out our [Contribution Guidelines](link-to-your-contribution-guidelines) for more information on how you can get involved.

## Bug Reports and Feature Requests

If you encounter any issues or have ideas for improvement, please [submit an issue](link-to-your-issue-tracker) on our GitHub repository.

## Contact

For general discussions and community support, visit our [Forum](link-to-your-forum).

## License

Vaporcito is licensed under the [MIT License](LICENSE), ensuring a fair and open use of the software.

---

**Note:** Vaporcito is a savegame-focused fork of an open-source continuous file synchronization engine (MPL 2.0).
