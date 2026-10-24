# Dedicated-user profile (opt-in)

Stage root-owned immutable releases, preserve existing settings/uploads/secrets,
and provide private systemd credentials before adopting `eirinchan.service`.
This is not an automatic migration of an existing instance. Review actual paths,
permissions, dependency services and host-wide memory budgets before activation.

Native Eirinchan retains authenticated distribution **on loopback only** because
weekly log cleanup invokes RPC in the running access-log writer. The native
launchers agree on `eirinchan@127.0.0.1`; protect COOKIE as root:service-group
0640. Container and gateway profiles disable distribution when it is not needed.
Do not use an independent `eval` process to purge the actively written access.log.

For this dedicated-user profile, pair the app service with
`eirinchan-private-log-retention.timer` and its service, retaining Monday midnight
in the VPS timezone. Do not enable both the legacy and isolated-profile timers.
The existing native installer continues using its matching legacy retention
wrapper/service. Review retained cookies and restart an already-running wildcard
EPMD only through a coordinated maintenance plan; setting an environment variable
does not rebind an existing daemon. Never rotate SECRET_KEY_BASE for this change.
