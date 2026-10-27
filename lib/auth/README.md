# Auth

Sign-in for Zig web apps: OAuth 2.0 providers (authorization code + PKCE) and
passkeys (WebAuthn).

```zig
const Auth = @import("auth");

const auth: Auth = .{
    .io = io,
    .userdata = &my_request_context,
    .vtable = &my_vtable,
    .origin = "https://example.com",
    .site_name = "Example",
    .home = "/dashboard",
    .providers = &.{Auth.OAuth.providers.github},
};
```

Construct one per request; it is a few pointers and costs nothing to build.

## What the app provides

| VTable entry | Purpose |
| --- | --- |
| `cookie`, `setCookie` | Read a request cookie; set one on the response. Copy every `Cookie` field as given. |
| `config` | Client id and secret for a provider, or null when it isn't set up. |
| `fetch` | Send an `OAuth.Request` and return the body of a 2xx response. |
| `authorize` | Whether an `Account` may sign in. Asked on every sign-in. |
| `putSession`, `getSession`, `deleteSession` | Store sessions, keyed by a SHA-256 hash of the cookie token. |
| `putPasskey`, `getPasskey`, `listPasskeys`, `usePasskey`, `deletePasskey` | Store passkeys. |

Only token hashes and public keys are ever handed to storage.

## Routes

| Method | Call | Then |
| --- | --- | --- |
| GET | `startOAuth(arena, provider, next)` | Redirect to the returned URL. |
| GET | `finishOAuth(arena, provider, .{ .state, .code, .error })` on `callback_path ++ provider` | Redirect to the returned path. |
| POST | `signOut()` | Redirect anywhere. |
| POST | `passkeyRequestOptions(arena)` | Send the JSON to `navigator.credentials.get`. |
| POST | `signInWithPasskey(arena, response_json, next)` | Redirect to the returned path. |
| POST | `passkeyCreationOptions(arena)` | Send the JSON to `navigator.credentials.create` (signed in only). |
| POST | `addPasskey(arena, response_json, name)` | Signed in only. |

`account(arena)` returns the signed-in `Account`, or null. Failures come back as
`Auth.Error` values (`error.Expired`, `error.NotAllowed`, …) for the app to turn
into messages.

Binary fields in the passkey JSON are base64url strings in both directions, so
the page script has to convert them to and from `ArrayBuffer`s.

## Behaviour

- Cookies get `Secure` and the `__Host-` prefix when `origin` is `https://`, and
  neither over plain `http://` (local development), where browsers refuse them.
- `next` paths are only followed when they stay on the site; otherwise sign-in
  lands on `home`.
- Every sign-in issues a fresh session token and drops the previous one.
- Passkeys require user verification, use "none" attestation, and belong to the
  provider account that registered them.

## Providers

`Auth.OAuth.providers.github` is built in. Any other authorization-code provider
is an `OAuth.Provider` value: its endpoints, scope, and a function that reads a
stable account id and display name from its user-info response.
