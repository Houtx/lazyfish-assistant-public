# Repository Instructions

## Repository Role

This public repository (`Houtx/lazyfish-assistant-public`) is the customer deployment and documentation entrypoint. The complete application is developed and released from the private `Houtx/lazyfish-assistant` repository. Its tag-triggered workflow publishes `ghcr.io/houtx/lazyfish-assistant-public:<version>` and moves `latest` for stable releases.

## Required Release Synchronization

Whenever a new stable application image is published:

1. Update the stable version shown in `README.md`.
2. Update the exact-version extraction example in `SOURCE.md`.
3. Search the repository for stale version references.
4. Compare application deployment changes with `docker-compose.yml`, `docker-compose.vnc.yml`, `global_config.yml`, and every installer script.
5. If Compose behavior, environment variables, ports, volumes, noVNC, licensing, initial login, data migration, or update behavior changed, update the corresponding customer documentation and deployment files.
6. If installer contents changed, run the deployment-kit tests, rebuild the Windows/macOS packages, and republish the installer assets.

Documentation-only version synchronization does not require rebuilding the application image or installer packages. Do not change `latest` wording to imply that running containers update automatically; customers must run the installer update flow or pull and recreate the service.
