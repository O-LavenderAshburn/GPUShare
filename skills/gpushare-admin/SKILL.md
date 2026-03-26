---
name: gpushare-admin
description: >
  Manage your GPUShare server — create invites, manage users, check stats,
  and monitor GPU status. For server operators who want to admin their
  instance through OpenClaw instead of the web UI.
metadata:
  openclaw:
    emoji: "🔧"
    requires:
      env:
        - GPUSHARE_API_URL
        - GPUSHARE_ADMIN_KEY
    primaryEnv: GPUSHARE_ADMIN_KEY
---

# GPUShare Admin

You have admin access to a GPUShare server. Use this skill when the user
wants to manage their GPU-sharing server — inviting users, checking who's
active, adjusting balances, monitoring the GPU, or viewing system stats.

## Configuration

- `GPUSHARE_API_URL`: The server URL (e.g. https://gpu.example.com)
- `GPUSHARE_ADMIN_KEY`: Admin API key (starts with `gpus_sk_`)

All requests need: `Authorization: Bearer ${GPUSHARE_ADMIN_KEY}`

---

## Available Actions

### Invite a new user
Create a one-time invite link that auto-provisions an account and API key.

```
POST ${GPUSHARE_API_URL}/v1/admin/invites
Content-Type: application/json

{
  "name": "Cole",           // optional, for your reference
  "expires_in_days": 7      // optional, default 7
}
```

Response includes `invite_url` and `token`. Send the full URL to the
person — when they open it they'll see their API key and OpenClaw setup
instructions. The link is single-use.

### List all invites
```
GET ${GPUSHARE_API_URL}/v1/admin/invites
```

Returns all invites with their status (pending, claimed, expired).

### Delete an unclaimed invite
```
DELETE ${GPUSHARE_API_URL}/v1/admin/invites/{invite_id}
```

### List all users
```
GET ${GPUSHARE_API_URL}/v1/admin/users
```

Returns all users with email, name, status, role, balance, billing type,
services enabled, and creation date.

### Get a single user
```
GET ${GPUSHARE_API_URL}/v1/admin/users/{user_id}
```

### Update a user
```
PATCH ${GPUSHARE_API_URL}/v1/admin/users/{user_id}
Content-Type: application/json

{
  "status": "active",                    // active | pending | suspended
  "role": "user",                        // user | admin
  "hard_limit_nzd": -20.00,             // spending limit
  "services_enabled": ["inference"]       // inference | render
}
```

Only include the fields you want to change.

### Adjust a user's balance
```
POST ${GPUSHARE_API_URL}/v1/admin/users/{user_id}/adjust-balance
Content-Type: application/json

{
  "amount_nzd": 5.00,
  "description": "Welcome credit"
}
```

Positive amounts add credit, negative amounts deduct.

### View system stats
```
GET ${GPUSHARE_API_URL}/v1/admin/stats
```

Returns: total users, active users, total inference cost, total render
cost, and jobs currently in queue.

### Check server status (no auth needed)
```
GET ${GPUSHARE_API_URL}/v1/status
```

Returns GPU info (name, VRAM, utilisation), loaded Ollama models, render
queue depth, estimated wait time, and electricity rate.

---

## Common Workflows

### "Invite my friend Cole"
1. Create an invite with name "Cole"
2. Share the invite URL with them
3. Tell the user: "Send Cole this link — when they open it they'll get
   their API key and OpenClaw setup instructions automatically."

### "Who's using the server?"
1. List users
2. Summarise: who's active, their balances, recent usage

### "Give everyone $2 credit"
1. List users to get IDs
2. Adjust balance for each user with amount 5.00

### "Is the GPU busy right now?"
1. Check /v1/status
2. Report: GPU utilisation, loaded models, queue depth

### "Suspend a user"
1. Find the user by listing users or by name/email
2. Update their status to "suspended"

---

## Error Handling
- **401 Unauthorized**: Admin key is invalid or the user isn't an admin
- **404 Not Found**: User or invite doesn't exist
- **503 Service Unavailable**: Server is offline

## Notes
- The admin key must belong to a user with `role: admin`
- Invite links are single-use and expire after the configured period
- Balance adjustments are append-only ledger entries (never modified)
- The /v1/status endpoint is public and doesn't require authentication
