# What the blocking Gemini review may reject for

This file is inlined into the reviewer's prompt as the whole list of blocking defects.
Everything it does not name is advisory.
Each item is a shape a reader can point at in a diff; the reviewer has the diff and nothing else.

- A correctness regression: the code does something other than what its names, its tests, or the surrounding code say it does.
- A security flaw: injection; a mutating route without an authorization check; a query that reads or mutates a tenant's data without the filter that scopes it to that tenant; a check removed from token or session verification; a secret, token, or key committed to the tree; a validation at a trust boundary removed.
- A data-loss defect: a record that can be silently dropped, overwritten, duplicated, or reordered; an update that resets fields the caller left out; a migration that drops or rewrites a column without carrying its data.
- A gate gamed, in any of these shapes:
  - a test deleted, skipped, or rewritten to match the behaviour that broke it;
  - a coverage threshold or a mutation-score threshold lowered in a test or Stryker config;
  - a type widened with `| undefined`, `| null`, `unknown`, or `any`, or a cast (`as`, `as unknown as`, a non-null `!` on a value that can genuinely be absent) added to silence an error rather than fix the assignment;
  - a schema loosened: a field made optional, a literal union swapped for a bare string, `.strict()` dropped from an input schema, `.passthrough()` or `.catch()` reached for because real data failed validation;
  - a lint or type-check's scope narrowed so findings stop being reported rather than stop existing: an `eslint-disable` without a stated reason, a rule weakened in the lint config, a `strict` flag turned off in `tsconfig`, a path added to an ignore list, a dead-code or dependency-cruiser exemption for something that is genuinely unused or circular.

<!--
Add your own shapes below, one bullet each, spelled out with the files they
apply to. The reviewer cannot open your docs, so a rule it cannot point at in
a diff is a rule it cannot enforce. Examples that earned their place:

- A privacy defect: user content written to a log, to an error tracker, or to
  a third party; free-text input stored where only a rating was meant to be;
  data moved outside the region the infrastructure pins.
- A design-system or i18n bypass: a colour, font, or spacing literal inlined
  in a screen where `src/theme/tokens.ts` has a token for it; a user-facing
  string hard-coded in a screen instead of added to the i18n table in every
  supported language.
- Shape drift: a vendor-specific branch added to a file the architecture names
  as shared (`src/adapters/shared.ts`) instead of the vendor's own module.
-->
