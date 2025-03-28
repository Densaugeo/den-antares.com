---
title: Navigating the Passkey Minefield
published_date: 2024-10-22 00:50:00.801888762 -0500
layout: post.liquid
excerpt_separator: <!-- END EXERPT -->
is_draft: false
---
<figure>
  <img src="/pics/navigating-the-passkey-minefield-smaller.webp"></img>
  <figcaption>How I felt taking on the passkey minefield. This pic might have some AI text artifacts, but passkeys have rough edges too so it fits!<figcaption>
</figure>

If you've ever used SSH keys to log into a remote shell and thought "This is so simple and easy, and private keys never have to be transmitted thanks to public key cryptography! Why don't we use this for logging into everything?" you're in luck: you can now set up your web site to accept logins based on public key cryptography and **never have to store passwords**. Unfortunately, the "simple and easy" part is a work in progress. Hence, the minefield.

## What's a "Passkey"?

Passkeys are public-private keypairs designed for logging in to web sites.

Passkeys are created when a user registers one on a web site. They're tied to the domain specified at registration, and aren't reused on different sites. When created, the public key is saved by the server for recognizing the user on future visits.

The private key is saved by the client software. It may be saved in an OS cloud service and tied to the user's Microsoft/Apple/Google account, or it may be saved in a password manager (1Password advertises support, though I haven't tested it), or in a hardware key such as a Yubikey.

On return visits, the client and server communicate to verify the authenticity of the private key. Depending on how a key was set up, the client may require the user to select from available keys or enter a PIN.

Overall, when set up well, this can create a streamlined and secure login - visit page, tap on prompt / enter PIN, and you are logged in! No SMS codes, no begging users to install a password manager, and you don't have to store passwords! Sounds good, but the bad news starts when you try to implement it...

<!-- END EXERPT -->

## I Can't Find Any Good Tutorials!

If you've set up auth systems before, you're probably expecting a framework where you import a library, select a few options, and maybe add a simple login page with a couple text boxes.

LOL.

If you've built your own password auth before, you might expect to look at a few tutorials or copy an example project.

LOL, again.

The few available passkey tutorials are mostly from Hanko and Corbado, auth vendors who are happy to give examples of how to connect to their cloud service. If you want to support passkeys **without** adding a new cloud dependency, it's going to be complicated.

I wrote this article as a guide to the parts I've figured out, and I hope it helps you understand how to create and recognize passkeys. However, this is for a very basic demo and if you want a full working system for a production site you're going to need to do a lot more work.

## Environment and Application

I set up passkey auth for a small section of my personal site where my account is the only one, so I don't need a new user signup process. I don't need account recovery either, since I can always SSH into my server and reset stuff manually if I need to.

I used the FastAPI Python framework on the backend (chosen mostly due to my familiarity with it), and web browser clients on the frontend. Since public keys are completely safe to publish and I only have a few of them, I just hardcoded my public keys into the server script instead of dealing with a database.

You can see the full code for this implementation in [its git repo](https://github.com/Densaugeo/tir-na-nog). This article is based on [this commit](https://github.com/Densaugeo/tir-na-nog/commit/c7ae004de8d6797ae4ce7fb98804da1577e390a0).

## Stage 0: Backend Library (Python)

Obviously, to do something like this you're going to want a library. Fortunately, you have options here:
- "py_webauthn" is an up-to-date webauthn library that you can easily install with <text style="color:#8f8">`python -m pip install webauthn`</text>.
- "Python WebAuthN" is an unmaintained library you should not use. It is installed by running <text style="color:#f88">`python -m pip install py-webauthn`</text>.
- Make sure you don't accidentally run <text style="color:#f88">`python -m pip install py-webauthn`</text> when trying to install py_webauthn - always use <text style="color:#8f8">`python -m pip install webauthn`</text>!

It's probably not *that* hard to handle passkeys without a backend library, but you'd need to handle specialized passkey messages that are probably some sort of struct packed into a binary buffer with some cryptographic signatures. That's not convenient in either Python or Javascript, but this is one of the few bits of passkey handling that a library can currently do for you, so take advantage.

## Stage 1: Challenge

Passkey login and registration both begin with the server sending a challenge to the client, consisting of randomly generated bytes. Python docs say `os.urandom()` is suitable for cryptographic use, and MDN recommends 16 bytes of entropy, so that's what I use.

The allowed credentials aren't used for registering new keys, but they are useful for logging in with a previously registered key, as you'll see later. `registered_keys` is a list where I store all my public keys (also covered later).

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

The client doesn't need to do much here, just fetch the challenge from the server.

```javascript
const challenge = await fetch_json('/api/challenge', { method: 'POST' })
```

The challenge is being saved in a global variable on the server, so what happens if several users are trying to log in at the same time? My server only has one account, so I don't care!

## Stage 2: Credential Creation

Before registering a new key, the client needs to create a credential object using the WebAuthn API located at `navigator.credentials`. Calling `navigator.credentials.create()` causes the browser to ask the user to create a passkey using built-in OS features, a hardware key, or a password manager. Details vary by implementation but it will return a credential object if successful.

```javascript
const credential = await navigator.credentials.create({
  publicKey: {
    challenge: b64_to_u8_array(challenge.challenge),
    rp: { id: domain, name: domain },
    rpId: domain,
    // The values in the 'user' field are never used later, they don't matter
    // but will throw an error if left empty
    user: {
      id: new Uint8Array([0x20]),
      name: ' ',
      displayName: ' ',
    },
    pubKeyCredParams: [
      // Chrome logs a warning unless both of these algorithms are specified
      { type: 'public-key', alg: -7 },
      { type: 'public-key', alg: -257 },
    ],
  },
})
```

This is where a lot of the decision-making (and pitfalls) in a passkey implementation happen.

The relying party ID is your domain name. In passkey terminology, "relying party" is the server the user is authenitcating to. As of tests I did on 11 Aug 2024, the RP ID must be supplied in two different ways:
- A `rp` object with `id` and `name` fields (new way).
- An `rpId` string (old way).
- Both must be supplied or many browsers will return an error.
- [MDN documentation](https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions) doesn't even mention `rpId` any more, even though it's still required.
- Most passkey guides only mention one or the other of these, but not both.

The user ID in its various forms is mainly for clients to show to users when selecting between different keys, which I've left as a placeholder here because there's only one user account on my personal site. For a real implementation, you'd want to use a username or e-mail or something like that.

This is also where you choose between resident and non-resident keys. This is discussed in detail in a later section, but for most applciations I recommend using the default (non-resident).

## Stage 3: Registration

The data from the newly created credential needs to be sent to the server. The only trick here is making sure all the necessary fields get included and binary buffers are encoded for transmission.

```javascript
const domain = location.hostname === 'localhost' ? 'localhost' :
  'den-antares.com'

const registration = await fetch_json('/api/register-key', {
  method: 'POST',
  body: JSON.stringify({
    id: credential.id,
    rawId: buffer_to_b64(credential.rawId),
    response: {
      attestationObject: buffer_to_b64(credential.response.attestationObject),
      clientDataJSON: buffer_to_b64(credential.response.clientDataJSON),
    },
    type: credential.type,
    
    // rpId and origin aren't part of the credential, but are needed because
    // pywebauthn checks them. They can't be hardcoded because they'll differ
    // between test and production, or even between different production hosts
    rpId: domain,
    origin: location.origin,
  }),
})
```

The server code to process the new credential is a bit more involved, but the core is `webauthn.verify_registration_response()`, which checks that the credentials are formatted correctly.

```python
@app.post('/api/register-key')
async def post_api_register_key(request: Request):
    global challenge
    if challenge is None:
        raise HTTPException(422, 'Unprocessable Content - Challenge not set')
    challenge_local = challenge
    challenge = None
    
    try:
        body = json.loads(await request.body())
    except json.decoder.JSONDecodeError:
        raise HTTPException(400, 'Bad Request - Invalid JSON')
    
    if body['rpId'] not in ['localhost', 'den-antares.com']:
        raise HTTPException(403, 'Forbidden - This key is for '
            f'"{body['rpId']}", not this site')
    
    try:
        verified_registration = webauthn.verify_registration_response(
            credential=body,
            expected_challenge=challenge_local,
            expected_rp_id=body['rpId'],
            expected_origin=body['origin'],
            require_user_verification=False,
        )
    except webauthn.helpers.exceptions.InvalidRegistrationResponse as e:
        raise HTTPException(401, f'Unauthorized - {e}')
    
    return fr.JSONResponse({
        'id': str(
            base64.b64encode(verified_registration.credential_id),
            'ascii'),
        'public_key': str(
            base64.b64encode(verified_registration.credential_public_key),
            'ascii'),
    })
```

The RP ID has two possible values (one for test and one for production).

## Stage 4: Public Key Storage

Normally the credential ID and public key would be saved in a DB here, but this is a small site with one user account so I don't have a DB. Instead I have the registration function return them in a JSON response, display them in a `<p>` tag, and then copy paste the values into a hardcoded list of accepted keys:

```python
@dataclasses.dataclass
class RegisteredKey:
    id: str
    public_key: str

registered_keys = [
    RegisteredKey( # localhost - Yubkey 5 NFC
        id='iEz0VA4zLJeDDQqmDsFxwyPsni1lCVAAevIEMKrruFfoVPIf1FYZJ8usYDTkjqH/tB1'
            'CpVQg71LrTChfpoAU9w==',
        public_key='pQECAyYgASFYIMX4QOP5gvEQH2nuQbjQ/1OoeiZ9mTWzN8LvLaSKVFjMIlg'
            'gLot+HtQvjuTuUJGOQ+3o34QzlFvP8uu7EV66bTzIFs0=',
    ),
    # ...more keys...
]
```

While not really practical for a normal account system, this technique is extremely useful for small sites with limited accounts: no database needed, and the keys are completely safe to post publicly so you can just throw them right into your repo and not worry about storing cryptographic secrets.

I have 6 passkeys registered right now, since I have 3 Yubikeys and separate passkeys are required for test and production domains. Noting which is which in comments works well enough.

## Stage 5: Challenge Again

After a passkey is registered, you can use it for logins. Logging in starts with the same challenge used for registration.

## Stage 6: Credential Checking

To prove identity, the client needs to sign a message which includes the random challenge with the passkey's private key. Since the private key is stored elsewhere, the client needs to talk to the OS, password manager, hardware key, or whatever device the key is stored on. This is done with `navigator.credentials.get`.

```javascript
const domain = location.hostname === 'localhost' ? 'localhost' :
  'den-antares.com'

const credential = await navigator.credentials.get({
  publicKey: {
    challenge: b64_to_u8_array(challenge.challenge),
    // rp is the new way, rpId is the old way. Both must be supplied for auth
    // to work in current browsers (as of 11 Aug 2024). How long until they
    // change it again?
    rp: { id: domain, name: domain },
    rpId: domain,
    allowCredentials: challenge.allowCredentials.map(v => { return {
      type: 'public-key',
      id: b64_to_u8_array(v),
    }}),
  }
})
```

This is also where that `allowCredentials` field return by the challenge endpoint is used: `navigator.credentials.get` uses it to check which stored passkeys can be used. For a serious login system, you'd need to send the list of credentials associated with a user, but with only account that's a lot simpler.

## Stage 7: Authentication

Finally, it's time to authenticate! It took a long time to get here (and some more time to get this part right too), but I eventually got all the different bits set up just right.

Next, the signed credential needs to be sent to the server.

```javascript
await fetch_text('/api/login', {
  method: 'POST',
  // pywebauthn is designed to use a stringified PublicKeyCredential object.
  // This works fine when the client runs in Firefox, but in Chrome running
  // JSON.stringify(credential) returns '{}', so it has to be rebuilt with
  // each important field explicitly reassigned. Maybe another security
  // mechanism gone wrong?
  body: JSON.stringify({
    id: credential.id,
    rawId: buffer_to_b64(credential.rawId),
    response: {
      authenticatorData: buffer_to_b64(credential.response.authenticatorData),
      clientDataJSON: buffer_to_b64(credential.response.clientDataJSON),
      signature: buffer_to_b64(credential.response.signature),
    },
    type: credential.type,
    
    // rpId and origin aren't part of the credential, but are needed because
    // pywebauthn checks them. They can't be hardcoded because they'll differ
    // between test and production, or even between different production hosts
    rpId: domain,
    origin: location.origin,
  }),
})
```

Then the server can verify the credentials using the public key saved earlier. The core of this is the `webauthn.verify_authentication_response()` function.

```python
@app.post('/api/login')
async def post_api_login(request: Request):
    global challenge
    if challenge is None:
        raise HTTPException(422, 'Unprocessable Content - Challenge not set')
    challenge_local = challenge
    challenge = None
    
    try:
        body = json.loads(await request.body())
    except json.decoder.JSONDecodeError:
        raise HTTPException(400, 'Bad Request - Invalid JSON')
    
    if body['rpId'] not in ['localhost', 'den-antares.com']:
        raise HTTPException(403, 'Forbidden - This key is for '
            f'`{body['rpId']}`, not this site')
    
    for key in registered_keys:
        if key.id == body['rawId']:
            public_key = base64.b64decode(key.public_key)
            break
    else:
        raise HTTPException(403, 'Forbidden - Key ID not found in registered '
            'keys')
    
    try:
        verified_response = webauthn.verify_authentication_response(
            credential=body,
            expected_challenge=challenge_local,
            expected_rp_id=body['rpId'],
            expected_origin=body['origin'],
            credential_public_key=public_key,
            # Sign count is required, but doesn't seem to do anything
            credential_current_sign_count=0,
            require_user_verification=False,
        )
    except webauthn.helpers.exceptions.InvalidAuthenticationResponse as e:
        raise HTTPException(401, f'Unauthorized - {e}')
    
    token = str(base64.b64encode(os.urandom(32)), 'ascii')
    tokens.append(token)
    res = fr.PlainTextResponse(token)
    res.set_cookie(key='token', value=token)
    return res
```

Once the login is verified, the server can generate a token for use in future requests.

## Resident vs. Non-Resident Keys

Passkeys can be resident or non-resident. (Some passkey purists will tell you that only one or the other counts as a true "passkey" and the other is really just a credential or something, but I'm not interested in those debates).

A resident passkey is the simpler case to understand: A new private key is generated and stored by the OS, password manager, or hardware key.

A non-resident passkey is derived on the fly by combining the credential ID with a master key. The end result is similar, but does not require storing a separate key.

The difference is most obvious with hardware keys. For example, a Yubikey 5 NFC can store up to 25 resident passkeys, or an **unlimited** number of non-resident passkeys (since non-resident passkeys don't actually require it to store anything).

Another difference is discoverability. Resident passkeys are sometimes referred to as "discoverable passkeys", because you can open Yubikey's management app and see which resident keys are stored - but you can't see which non-resident keys are stored, since nothing is actually stored for them.

A final difference is that in my testing, resident keys usually also require the user to enter a PIN whenever logging in. This requirement is especially burdensome for Yubikeys, because the only mechanism for requiring a PIN on a Yubikey makes it required for **all** use of that Yubikey, even for using it with unrelated web sites.

Despite the usability issues with resident passkeys, it may still be worth using them if you are using passkeys alone with no password, **and** physical device or key theft is a concern for your users. Otherwise, I recommend sticking with non-resident passkeys until the storage and PIN usability issues are sorted out.

If resident passkeys are necessary for your application, they can be created by supplying the approriate options to `navigator.credentials.create()`, [documented on MDN](https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions).

## Testing

Testing passkey login has a few complications:
- Passkeys APIs are only available on HTTPS pages.
- Passkeys APIs are not available if there are any HTTPS errors on a page.
- Each passkey is tied to a domain name.
- If the domain name supplied to `navigator.credentials` is not a subdomain of the passkey's linked domain, it'll error out.

This means that setting up a test system will generally involved making some SSL certs, as well as test passkeys for your test domain. The git repo for this project shows a basic test setup using `localhost`. This doesn't allow testing on mobile, but my site is small enough that I just tested mobile in production.

When I [asked around on Reddit](https://www.reddit.com/r/webdev/comments/1epstuv/is_it_possible_to_set_up_a_test_server_for_a/), someone reported they got mobile testing to work using the TunnelTo service.

## But What About [1001 things that can go wrong]?

There's a lot that can go wrong with passkeys.
- **User made a passkey on a Windows PC and wants to log in on their iPhone (or vice versa).** Passkeys support authentication through an external device using a complex process involving QR codes, Bluetooth, and Apple supposedly cooperating with other companies. You can try, but it probably won't work.
- **User made a passkey on their phone and then lost the phone.** If the passkey was saved to a cloud account, they can get a new phone and it will probably sync when they log into their Apple/Google account.
- **User's Apple/Microsoft/Google account that holds their passkeys was hacked.** The attacker now has full control of all of the user's passkey accounts. Advise the user they are screwed. They could change their name, join the French Foreign Legion, and start a new life.
- **User made a passkey on their tablet, which they left at home.** It'll sync to their device if they both have the same OS. And are logged in to the same account. User doesn't dutifully buy all their gadgets from the same tech giant? They should have thought of that earlier. Did you think passkeys wouldn't require user education?
- **User is on Linux.** Buy a Yubikey.
- **User's Microsoft account merged with one of their 4 other Microsoft accounts and now they can't find their passkeys.** Some cities now have shops where you can pay to smash stuff with a sledgehammer. I've heard alcohol can help too.

Not a complete list, of course.

Passkeys are new and still have many kinks. Even when they work correctly, most users aren't familiar with them. Any serious passkey deployment must have an alternate login option - I recommend e-mail or social login, since one of the biggest advantages of passkeys is not having to store passwords.

I've also found that many of the failure modes of passkeys can be avoided by using a Yubikey, rather than the built-in OS passkeys. The main caveat is that regular users are not going to buy Yubikeys (fortunately not a concern for this small test site).

## Quality Level of Passkey APIs

While implementing passkeys I ran into some concerning quality issues:
- The [best existing example I found](https://gist.github.com/samuelcolvin/3ff019aa738aa558a185c4fb002b5751) doesn't work any more.
- In Firefox, there is a [known bug](https://stackoverflow.com/questions/62717941/why-navigator-credentials-get-function-not-working-in-firefox-addon) which prevents `navigator.credentials.get()` from working when run from the browser console. The [Bugzilla](https://bugzilla.mozilla.org/show_bug.cgi?id=1479500) [issues](https://bugzilla.mozilla.org/show_bug.cgi?id=1448408) for it were closed years ago but the bug is still there.
- The RP ID must be supplied to `navigator.credentials.create()` using two different formats, one of which is not listed in the [MDN documentation](https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions).
  * Note that the "old way" which is currently deprecated-but-still-required wasn't vendor-prefixed. It was an actual web standard.
- Like many security technologies, passkeys are [hostile to testing](https://www.reddit.com/r/webdev/comments/1epstuv/is_it_possible_to_set_up_a_test_server_for_a/).

I don't know what's going on inside the organizations behind passkeys, but based on what I can see of the state of documentation and bug fixes, I'm not convinced they can create robust security tools. Will a team that leaves obvious bugs unfixed for years be able to keep up with security fixes? Will companies that publish new security tools with no documentation or examples be careful of how their tools interact with real users in the wild?

Passkeys are useful for smaller use cases where you don't want to take on the risks of storing passwords, but I can't recommend them for anything high-security until the serious quality issues in passkey APIs are addressed.

## Web Standards Aren't Forever Any More

If you built a standards-based web site before 2015, you might feel quite smug now - web standards didn't change like the hot frameworks, and your old web site likely works just as it did years ago.

If you built a standards-based web site in 2017 using `SharedArrayBuffer`, that feature was [removed for security reasons](https://blog.mozilla.org/security/2018/01/03/mitigations-landing-new-class-timing-attack/) and re-enabling it [took years](https://github.com/tc39/ecma262/issues/1435).

Web standards aren't nearly as permanent as they used to be, and modern standards like WebAuthn undergo breaking changes (such requiring the `rpId` string to also be supplied in an `rp` object as well). Standards-compliant demos from a couple years ago do not work on current browsers due to this.

An important consideration when adopting passkeys is that they are both very new and very security sensitive - they are far more likely to undergo breaking changes than most web standards, and you cannot assume that future browsers will be backwards compatible with current passkey sites.

## Summary

The Good:

- When they work, passkeys are as convenient as a Yubikey.
- Passkeys CAN let you avoid storing passwords.
- Passkeys are highly resistant to phishing. This protection isn't as good as it sounds, since any present-day passkey implementation will need alternate login options that can be phished, but it can offer some benefit to users who rarely use other login options.

The Bad:

- There's a LOT of edges cases that aren't handled well.
- Passkeys aren't going to work for every user.
- Resident passkeys suffer from usability problems, especially when using hardware keys.
- Testing passkeys on mobile is excessively complicated.
- Libraries are in flux, and you need to figure a lot of stuff out yourself.

The Very Bad:

- Breaking changes in the relevant W3C standards.
- Core passkey components like OS and browser support have a concerning number of bugs.

They're definitely a mixed bag, but I expect to use passkeys more in the future because they are a great fit for custom web services with single-digit user counts, which I find myself building frequently.

For low- or medium-security sites with higher user counts, they can be used today as a convenient login option security-savvy users, but aren't going to work well as a primary login method for most users.

For high security sites, passkeys should not be used until implementations have matured significantly and quality issues have been addressed.

## Sources

Git repo where I used passkeys: <https://github.com/Densaugeo/tir-na-nog>.

Git commit this article is based on: <https://github.com/Densaugeo/tir-na-nog/commit/c7ae004de8d6797ae4ce7fb98804da1577e390a0>.

MDN documentation for `navigator.credentials.create()` options: <https://developer.mozilla.org/en-US/docs/Web/API/PublicKeyCredentialCreationOptions>.

Reddit thread on setting up tests for passkey sites: <https://www.reddit.com/r/webdev/comments/1epstuv/is_it_possible_to_set_up_a_test_server_for_a/>.

Best existing passkey example: <https://gist.github.com/samuelcolvin/3ff019aa738aa558a185c4fb002b5751>.

Stack Overflow thread on Firefox's WebAuthn console bug: <https://stackoverflow.com/questions/62717941/why-navigator-credentials-get-function-not-working-in-firefox-addon>.

Bugzilla issue on WebAuthn console bug: <https://bugzilla.mozilla.org/show_bug.cgi?id=1479500>.

Bugzilla issue on attempted fix for WebAuthn console bug: <https://bugzilla.mozilla.org/show_bug.cgi?id=1448408>.

Mozilla announcement of `SharedArrayBuffer` removal: <https://blog.mozilla.org/security/2018/01/03/mitigations-landing-new-class-timing-attack/>.

Discussion of changes to `SharedArrayBuffer` standard: <https://github.com/tc39/ecma262/issues/1435>.
