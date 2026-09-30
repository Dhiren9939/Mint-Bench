# Predictions, written before the first run

The idea: the rate limiter (Bucket4j `casBasedBuilder` over one Lettuce connection) has hot keys, every request from
every user hits the same GLOBAL and IP buckets, and once enough requests collide the CAS retries collapse the throughput.

If that's right:

1. The knee shows up as a cliff, not a slope. Requests per second stop rising or fall while the users go up, and cpu was not
   maxed just before it.
2. Redis commands per request (bench window) is flat at a low number below the knee and goes up a lot above it.
3. The thread dumps taken in the middle of a failing bench show a lot of Tomcat threads inside Bucket4j / Lettuce (waiting on
   the redis connection), not inside Hikari or the database.
4. Redis cpu goes up while requests per second go down.

If it's wrong:

- Commands per request stays flat through the knee, threads sit somewhere else (Hikari getConnection, GC) or mostly idle.

Also checking: does the `MINT_ID` cookie get reused? It's Secure in prod, and k6 talks http, so every request may create a new
per-user bucket key. If so new keys per request is about 1, and the keys grow by rps x 60 before they expire.

Local cores are faster than a t3, so the knee will not be at 1420 users.
