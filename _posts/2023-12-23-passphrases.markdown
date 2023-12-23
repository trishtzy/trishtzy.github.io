---
layout: post
title:  "The case for passphrase"
date:   2023-12-23 23:30:00 +0800
categories: blog
---
<script src="https://cdn.mathjax.org/mathjax/latest/MathJax.js?config=TeX-AMS-MML_HTMLorMML" type="text/javascript"></script>

Recently, I have been cleaning up accounts that are flagged as potential risk for password leak. It has been a terrible yet interesting user experience to reset my password from various sites.

Not all websites allow passphrases to be your password. Especially, traditional banks. They impose a one-word-alphanumeric-and-symbols kind of password. Take Standard Chartered for example,

![Password Reset for Standard Chartered Online Banking](./../../../../assets/img/stanchart-screenshot.png)

What does a strong password mean? Cryptographers measure it using entropy, a mathematical approximation of password strength. In other words, how resistant it is to computers guessing by brute force.

Password entropy is expressed in terms of bits and this is the formula to calculate it:

$$E = log{_2}(R^L) \implies  E = L * log{_2}R$$

$$R$$ is the number of unique characters allowed in the password
$$L$$ is the number of characters of the password

What this means is the higher the entropy, the more complex it is for the attacker to guess. We can also deduce from the formula that increasing either the password length, $$L$$ or using more characters $$R$$, will strengthen the password[^2].

Let's calculate the entropy range from the Standard Chartered example.

Characters allowed|Pool Size
---|:---:
A-Z|26
a-z|26
0-9|10

$$ R = 26 + 26 + 10$$

$$E = 8 * log{_2}(62)$$

$$E = \text{47.6335704831 bits}$$

$$ E = 16 * log{_2}(62)$$

$$E = \text{95.2671409662 bits}$$

So the entropy range Standard Chartered set is 47.6 to 95.2 bits.

If we use a passphrase with only lower and uppercase characters, with words separated by a hyphen, the entropy will be higher:

$$E = (5 * 3 + 3) * log{_2}(26 * 2)$$

A passphrase is a string of words. So let's assume a minimum of three words with an average of 5 characters.

$$E = \text{102.607914927 bits}$$

With a passphrase, your password entropy is **minimally** 102.6 bits, higher than the maximum value from Standard Chartered.
This means that it will take $$2^7$$ more guesses to break the passphrase.

Besides entropy, **passphrases are much easier to remember** because you can make word connections. For example you can have a password like `baking-strawberry-pie` with an entropy of 119.7 bits. That is still extremely resistant to a machine that can make 2 billion guesses per second[^1].

The best way to secure your online accounts is to **use a password manager** like 1Password or Bitwarden. It is able to generate a unique passphrase for every account and auto-fill from your browser or mobile. You should also enable 2FA where possible as relying on strong passwords alone is not sufficient.

Let's leave complicated password rules to fun games like https://neal.fun/password-game/ instead.

#### Footnotes

[^1]: https://alecmccutcheon.github.io/Password-Entropy-Calculator/
[^2]: https://www.omnicalculator.com/other/password-entropy
