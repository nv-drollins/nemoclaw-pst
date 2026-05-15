---
name: pst-mail
description: Search and summarize a local sample Outlook PST mailbox. Use for questions about Outlook, PST files, mailbox folders, Inbox, Sent Items, email counts, latest emails, senders, subjects, and date ranges.
---

# PST Mail

The PST mailbox is already configured on the host. Do not ask the user for a PST path, Outlook login, Microsoft 365 account, or OAuth credentials.

Use `curl` against the local PST service at `http://127.0.0.1:9003`. For this demo, do not use alternate hostnames such as `host.openshell.internal`. If the loopback service is not reachable, report that the PST service is unreachable and stop instead of retrying other routes.

Use short request timeouts so a missing service does not stall the agent turn:

```bash
curl -fsS --max-time 10 http://127.0.0.1:9003/folders
curl -fsS --max-time 10 http://127.0.0.1:9003/emails/count
curl -fsS --max-time 10 'http://127.0.0.1:9003/emails/latest?count=5'
curl -fsS --max-time 10 'http://127.0.0.1:9003/emails/search_subject?keyword=attachment&max_results=5'
curl -fsS --max-time 10 'http://127.0.0.1:9003/emails/search_sender?sender=saqib&max_results=5'
```

When reporting results, summarize folder counts or matching emails clearly. Include subjects, folders, senders, dates, and a short body excerpt when useful.
