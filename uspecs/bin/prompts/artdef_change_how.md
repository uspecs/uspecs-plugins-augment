# How section

## data

Append to the Change File a `## How` section describing the implementation approach - strategy, patterns, and technologies - in the format below:

```markdown
## How

- Use existing middleware pipeline in `src/app.ts` to add authentication layer
- Add `middleware/auth.middleware.ts` leveraging OAuth 2.0 library for token handling
- Store sessions in Redis using `config/redis.config.ts` for horizontal scalability

References:

- [src/app.ts](../../../src/app.ts)
- [middleware/auth.middleware.ts](../../src/middleware/auth.middleware.ts)
- [config/redis.config.ts](../../../src/config/redis.config.ts)
```

Rules:

- Focus on approach, not detailed design
- Keep it concise - an idea, not a full plan
- End with a References list that collects links to all files mentioned in the approach
