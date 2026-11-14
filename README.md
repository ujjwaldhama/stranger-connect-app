# Backend plan (Phase 2)

The Flutter app currently contains a visual starter only. No real accounts, matching, messages, payments, or persistent data are connected yet.

Recommended backend:
- Python FastAPI
- PostgreSQL for users, friend links, chat sessions, reports, ratings and subscriptions
- WebSockets for real-time chat
- Redis for the waiting queue and online presence
- JWT access tokens with secure password hashing
- Admin endpoints protected by role-based access control

Privacy and safety requirements:
- Never expose another user's Telegram ID, phone number, email, IP address, or internal database ID.
- Use opaque public user IDs and server-authorized chat session IDs.
- Add block/report, rate limits, age-appropriate safeguards, moderation and account deletion.
- Store only data needed to operate the service; define retention periods.
- Verify subscription payments on the server, never trust a client-side premium flag.
