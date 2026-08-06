# Security

- Never interpolate user input into SQL. Parameterised queries or `where(key: value)`.
- Always strong parameters. Never `params.permit!`.
- Every controller authenticates unless it is deliberately public.
- Scope every query to the current user, or authorise with Pundit.
- Never `raw`, `html_safe`, or `<%==` with anything a user supplied.
- Never skip CSRF verification on a browser-facing controller.
- Never `render json: model` without an explicit `only:`. Whitelist the attributes.
- Never redirect to `params[:return_to]` without validating it.
- Array form for shell commands: `system("cmd", arg)`, never `system("cmd #{arg}")`.
- Filter passwords, tokens, secrets, and API keys out of the logs.
- `cookies.signed` rather than `cookies`.
- `config.sandbox_by_default = true` in production-like environments, so a console session
  can't write by accident.
- ActiveStorage for attachments.
