# Test credentials (no one-tap login)

For pilot testing, normal phone+OTP login accepts fixed test accounts. This is controlled by:

```text
TEST_OTP=123456
```

When `TEST_OTP` is set, these numbers skip SMS and accept that OTP:

| Role | Phone | OTP |
|---|---|---|
| Rider | +254712345678 | 123456 |
| Driver | +254700000001 | 123456 |
| Dispatch | +254700000010 | 123456 |
| Safety | +254700000011 | 123456 |
| Admin | +254700000012 | 123456 |

## Rider app

- Number is prefilled with **+254712345678**
- Tap **Send code** — the test code is filled automatically
- Tap **Verify and continue**

## Driver app

- Number prefilled with **+254700000001**
- Tap **Send code**, then **Verify and continue**

## Dispatch console

- Phone prefilled with **+254700000010**
- Tap **Send code** — the dev/test code is shown/filled
- Tap **Open console**

The safety/admin test numbers can also be entered manually on the dispatch login.

## Disabling before launch

Remove/blank `TEST_OTP` in Render (or set it to an empty string), then redeploy.
Fixed numbers then require normal SMS OTP; the test hint stays harmless.

- Rotate `JWT_SECRET` if the URL was shared while test OTP was enabled.
- Keep `DISPATCH_PHONES` restricted to real ops numbers for production.
