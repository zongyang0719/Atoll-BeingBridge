# Being Notch

Being Notch puts a Being’s live state and a narrow Soul chat into the Mac
notch through Atoll.

- The closed notch shows the same high-level state that Loom exposes:
  thinking, working, or replying.
- Hovering opens a compact, scrollable reply view with one input field.
- Unsent text survives a hover-close and WebView rebuild; it never goes to
  Being until you send it.

It is a local bridge, not an Atoll fork. Atoll must be installed separately.

## Install

Requirements:

- macOS 14 or later. The bridge builds universal arm64/x86_64 slices; the
  Atoll build you install must support your Mac too;
- Atoll installed and running;
- a Being URL copied from Loom. The URL must include its token query parameter.

Clone the repository, then run:

~~~sh
zsh install.sh
~~~

The installer creates a per-user LaunchAgent. Open the **Being** tab in Atoll,
then paste one complete Being URL, choose **测试连接**, and **保存并连接**. The
bridge reads the Being name from the status endpoint; there is no separate
username field, provider page, or standalone settings app.

If you are replacing an older local bridge that already uses port 9021, the
installer leaves it running instead of interrupting it. Stop the older bridge,
then run `zsh install.sh` again.

## What is stored

The only secret is the pasted URL. It is written to:

~~~text
~/.being-notch/being-url
~~~

The file is set to owner-only permissions. It is not committed, logged, sent
to Atoll, or inserted into the embedded chat page. Non-sensitive rendering
settings live separately in ~/.being-notch/config.json.

The bridge listens only on 127.0.0.1. The tab talks only to that local bridge;
the bridge alone makes the status test and Being requests. The URL field is
cleared after a successful save and never enters an Atoll descriptor.

## Development

~~~sh
zsh scripts/verify-public.sh
zsh build.sh
~~~

The verification script checks for retired/private identifiers, likely literal
secrets in source files, required public files, and a full Swift build.

## Limits

- Atoll extension tabs accept 160–420pt total height.
- Embedded web content must stay below 20KB.
- Drafts live only in bridge memory. Restarting the bridge clears an unsent
  draft.
- Atoll updates can replace or change host behavior independently of this
  bridge.

## License and notices

Being Notch is MIT licensed. Third-party runtime and protocol notices are in
[NOTICE](NOTICE).
