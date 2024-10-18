---
title: Navigating the Passkey Minefield
published_date: 2024-10-18 17:00:00.801888762 +0000
layout: post.liquid
is_draft: false
---
If you've ever used SSH keys to log into a remote shell and thought "This is so simple and easy, and private keys never have to be transmitted thanks to public key cryptography! Why don't we use this for logging into everything?" you're in luck: you can now set up your web site to accept logins based on public key cryptography and **never have to store passwords**. Unfortunately, the "simple and easy" part is a work in progress. Hence, the minefield.

## What's a "Passkey"?

Passkeys are public-private keypairs designed for logging in to web sites.

Passkeys are created when a user registers one on a web site. They are tied to the domain specified at registration, and aren't supposed to be reused on different sites. When created, the public key is saved by the server so it can recognize the user on future visits.

The private key is saved by the client software. It may be saved in an OS cloud service and tied to the user's Microsoft/Apple/Google account, or it may be saved in a password manager (1Password advertises support, though I haven't tested that), or in a hardware key such as a Yubikey.

On return visits, the client and server communicate to verify the authenticity of the private key. Depending on how a key was set up, the client may require the user to select from available keys or enter a PIN.

Overall, when set up well, this can create a streamlined and secure login - visit page, tap on prompt / enter PIN, and you are logged in! No SMS codes, no begging users to install a password manager, and you don't have to store passwords!

## Overall Flow

```python
@app.post('/api/challenge')
async def post_prelogin():
    global challenge
    # MDN states the challenge should be at least 16 bytes
    # https://developer.mozilla.org/en-US/docs/Web/API/Web_Authentication_API
    challenge = os.urandom(16)
    return fr.JSONResponse({
        'challenge': str(base64.b64encode(challenge), 'ascii'),
        'allowCredentials': [v.id for v in registered_keys],
    })
```

## Code + Examples

## But What About [1001 things that can go wrong]?

| Problem | Solution (or "solution") |
|---|---|
| User made a passkey on a Windows PC and wants to log in on their iPhone (or vice versa). | Passkeys support authentication through an external device using a complex process involving QR codes, Bluetooth, and Apple supposedly cooperating with other companies. You can try, but it probably won't work. |
| User made a passkey on their phone and then lost the phone. | If the passkey was saved to a cloud account, they can get a new phone and it will probably sync when they log into their Apple/Google account. |
| User's Apple/Microsoft/Google account that holds their passkeys was hacked. | The attacker now has full control of all of the user's passkey accounts. Advise the user they are screwed. They could change their name, join the French Foreign Legion, and start a new life. |
| User made a passkey on their tablet, which they left at home. | It'll sync to their device if they both have the same OS. And are logged in to the same account. User doesn't dutifully buy all their gadgets from the same tech giant? They should have thought of that earlier. Did you think passkeys wouldn't require user education? |
| User is on Linux. | Buy a Yubikey. |
| User's Microsoft account merged with one of their 4 other Microsoft accounts and now they can't find their passkeys. | Some cities now have shops where you can pay to smash stuff with a sledgehammer. I've heard alcohol can help too. |

Not a complete list, of course.

Passkeys are new and still have many kinks. Even when they work correctly, most users aren't familiar with them. Any serious passkey deployment must have an alternate login option - I recommend e-mail or social login, since one of the biggest advantages of passkeys is not having to store passwords.

I've also found that many of the failure modes of passkeys can be avoided by using a Yubikey, rather than the built-in OS passkeys. The main caveat is that regular users are not going to buy Yubikeys.

## Recommendations

## Summary
