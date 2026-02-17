> **[QuickStart Guide →](./QuickStart.md)** — Get the platform running locally in under 5 minutes.

# OlympusOSS Identity Platform

A complete, enterprise-grade identity and access management platform built on [Ory](https://www.ory.sh/) open-source infrastructure. Designed for a single organization that needs full control over both customer and employee identity — without vendor lock-in or per-user pricing.

---

## The Problem

Most identity solutions force a choice: use a managed SaaS that controls your data and pricing, or build from scratch and maintain it forever. Both paths are expensive. Both are risky.

For a single company running its own products and services, the choice is even starker. You need separate identity systems for customers and employees, but managed providers charge per user across both — and managing two disconnected stacks doubles the operational burden. Meanwhile, customer expectations around login, consent, and privacy keep rising.

## The Solution

OlympusOSS Identity Platform delivers a unified identity architecture purpose-built for a single organization, with a clean separation between **customer identity (CIAM)** and **internal employee identity (IAM)** — all running on proven, battle-tested Ory infrastructure.

One company. Two identity domains. Complete isolation. Full control.

---

## Architecture

```
                    ┌─────────────────────────────────────────────────┐
                    │              Employee (IAM) Domain              │
                    │                                                 │
                    │   IAM Kratos ── IAM Hydra ── IAM Medusa        │
                    │   (identities)  (OAuth2)     (consent)         │
                    │        │                        │               │
                    │        ▼                        ▼               │
                    │   IAM Hera              IAM Athena             │
                    │   (authentication)      (Admin Panel)          │
                    │                         "Manage internal users" │
                    └────────────────────┬────────────────────────────┘
                                         │
                              admin authentication
                                         │
                    ┌────────────────────┴────────────────────────────┐
                    │             Customer (CIAM) Domain              │
                    │                                                 │
                    │   CIAM Kratos ── CIAM Hydra ── CIAM Medusa     │
                    │   (identities)   (OAuth2)      (consent)       │
                    │        │                          │             │
                    │        ▼                          ▼             │
                    │   CIAM Hera              CIAM Athena           │
                    │   (authentication)       (Admin Panel)         │
                    │                          "Manage customers"     │
                    └─────────────────────────────────────────────────┘
```

### Two Domains, One Platform

|                    | Customer (CIAM)                     | Employee (IAM)                        |
|--------------------|--------------------------------------|---------------------------------------|
| **Who**            | Your customers, end users, clients   | Your employees, admins, support staff |
| **Identity Store** | CIAM Kratos                          | IAM Kratos                            |
| **OAuth2 / OIDC**  | CIAM Hydra                           | IAM Hydra                             |
| **Consent**        | CIAM Medusa                          | IAM Medusa                            |
| **Authentication** | CIAM Hera                            | IAM Hera                              |
| **Admin Panel**    | CIAM Athena                          | IAM Athena                            |

Both admin panels are protected by the employee identity store. A customer can never access admin tooling — they exist in a completely separate identity pool.

---

## Projects

### Athena — Admin Panel

A modern, full-featured administration interface for managing identities and OAuth2 clients. Built with Next.js, TypeScript, and Material UI.

**Capabilities:**

- **Identity Management** — Create, view, update, and delete user identities. Full lifecycle management with audit-ready detail views.
- **Session Management** — Monitor active sessions across your user base. Revoke sessions individually or in bulk.
- **OAuth2 Client Management** — Register, configure, and manage OAuth2/OIDC clients. Full control over redirect URIs, grant types, scopes, and token lifetimes.
- **Schema Management** — Define and manage identity schemas to support different user types (customers, organizations, admins).
- **Message Tracking** — Monitor transactional emails and verification messages sent through the platform.
- **Dashboard & Analytics** — At-a-glance overview of identity counts, active sessions, and system health.

Athena is deployed twice: once as **CIAM Athena** (managing customer identities) and once as **IAM Athena** (managing employee identities). Both instances authenticate administrators through the employee identity store.

### Medusa — OAuth2 Consent Provider

A lightweight, purpose-built consent interface for Ory Hydra OAuth2 flows. Built with Next.js and TypeScript.

**Capabilities:**

- **Consent Flow** — Presents scope approval screens and handles user consent decisions during OAuth2 authorization requests.
- **Logout Flow** — Manages OAuth2 logout with proper session cleanup across identity and OAuth2 layers.

Medusa handles the OAuth2 consent step only — when an application requests access to user data, Medusa presents the scope approval screen and records the user's decision. It does not handle authentication; that responsibility belongs to Hera.

Medusa is deployed twice: **CIAM Medusa** handles consent for customer-facing OAuth2 clients, and **IAM Medusa** handles consent for internal tooling and services.

### Hera — Authentication UI

The authentication frontend for Ory Kratos. Handles all user-facing authentication flows including login, registration, and multi-factor authentication. Built with Next.js and TypeScript.

**Capabilities:**

- **Login Flow** — Authenticates users with email/password, social login, or passwordless methods against Ory Kratos.
- **Registration Flow** — Handles new user sign-up with configurable identity schemas.
- **MFA Flow** — Manages multi-factor authentication challenges (TOTP, WebAuthn, recovery codes).
- **Account Recovery** — Password reset and account recovery flows.
- **Account Settings** — Self-service profile updates, password changes, and MFA enrollment.

When Ory Hydra receives an OAuth2 authorization request, it redirects to Hera for authentication. Once the user is authenticated, Hydra redirects to Medusa for consent. This clean separation means authentication logic and consent logic are independently deployable and customizable.

Hera is deployed twice: **CIAM Hera** handles customer-facing authentication, and **IAM Hera** handles employee authentication for internal tools and admin panels.

---

## Why This Architecture

### Complete Domain Isolation

Customer data and employee data never mix. Separate databases, separate secrets, separate sessions. A breach in one domain cannot cascade to the other.

### Single Pane of Glass for Admins

Despite full isolation, administrators manage everything from the same familiar interface. CIAM Athena and IAM Athena are the same application — just pointed at different services.

### No Vendor Lock-In

Built entirely on Ory's open-source stack (Kratos + Hydra). No proprietary APIs, no per-seat pricing surprises, no data held hostage. You own everything.

### Standards-Based

OAuth2, OpenID Connect, and FIDO2/WebAuthn out of the box. Integrate with any application, any language, any framework.

### Compliance-Ready

The IAM/CIAM separation maps directly to regulatory boundaries. Customer PII is isolated from internal systems, making GDPR, SOC 2, and HIPAA audit scoping straightforward.

### Built to Scale

Each service scales independently. Customer traffic spikes don't affect internal admin tooling. Add capacity where you need it, when you need it.

---

## Cost Savings

Identity is one of the most expensive line items in a modern SaaS stack. Managed identity providers charge per monthly active user (MAU), and those costs compound fast as your customer base grows. OlympusOSS Identity Platform eliminates that entirely.

### vs. Managed Identity Providers

|                            | Auth0         | Okta                                             | Ory Network                            | OlympusOSS Identity Platform |
|----------------------------|---------------|--------------------------------------------------|----------------------------------------|------------------------------|
| **Pricing model**          | Per MAU       | Per MAU                                          | Per aDAU (avg daily active)            | Fixed infrastructure cost    |
| **10K users/mo**           | ~$228/mo      | ~$200/mo                                         | ~$210/mo                               | $0 (beyond hosting)          |
| **100K users/mo**          | ~$1,900/mo    | ~$2,000/mo                                       | ~$1,470/mo                             | $0 (beyond hosting)          |
| **1M users/mo**            | ~$19,000/mo   | ~$15,000+/mo                                     | ~$14,070/mo                            | $0 (beyond hosting)          |
| **Separate CIAM + IAM**    | 2x the cost   | Separate product (Workforce + Customer Identity) | Separate projects                      | Built-in                     |
| **Data ownership**         | Vendor-hosted | Vendor-hosted                                    | Ory-hosted (or self-hosted enterprise) | You own it                   |
| **Custom consent flows**   | Limited       | Limited                                          | Full control (headless)                | Full control                 |
| **OAuth2 server included** | Add-on cost   | Add-on cost                                      | Built-in (full Hydra)                  | Built-in (full Hydra)        |

**At 100K monthly active users, OlympusOSS Identity Platform saves $20,000 - $24,000 per year compared to Auth0 or Okta.** At 1M users, savings exceed $180,000/year. The cost is running a few lightweight containers and a PostgreSQL instance.

### How the Savings Break Down

**Zero per-user fees.** Ory Kratos and Hydra are open-source with Apache 2.0 licensing. There is no usage-based pricing. Whether you have 100 users or 10 million, the software cost is zero.

**Shared infrastructure, isolated domains.** Both CIAM and IAM run on a single PostgreSQL instance with logical database separation. You don't need to provision and pay for two completely separate infrastructure stacks. One database server, one container orchestrator, two identity domains.

**One codebase, multiple deployments.** Athena, Medusa, and Hera are each a single project deployed as multiple containers with different environment variables. This means one CI/CD pipeline per project, one set of dependencies to maintain, one codebase to audit — but six distinct services in production. A fraction of the maintenance cost of building separate UIs for customers and employees.

**No OAuth2 add-on costs.** Managed providers often charge extra for OAuth2/OIDC server capabilities, or limit the number of clients and connections. Ory Hydra provides a full-featured, certified OAuth2 and OpenID Connect server with no limits on clients, connections, or token grants.

**No premium feature gates.** Features like MFA/TOTP, custom identity schemas, passwordless login, session management, and admin APIs are available by default. Managed providers typically gate these behind enterprise tiers that can cost 3-5x the base price.

### Infrastructure Cost Estimate

Running the full platform (both IAM and CIAM domains) in production:

| Resource                             | Specification                     | Estimated Cost   |
|--------------------------------------|-----------------------------------|------------------|
| PostgreSQL                           | Single instance, 2 vCPU / 8GB RAM | ~$50-100/mo      |
| Application containers (10 services) | Lightweight, ~256MB each          | ~$50-100/mo      |
| **Total**                            |                                   | **~$100-200/mo** |

This is a **fixed cost** that does not increase with user count. At scale, the savings are dramatic:

| Monthly Active Users | Managed Provider (avg) | Ory Network (est.)  | OlympusOSS Identity Platform | Annual Savings vs Managed |
|----------------------|------------------------|---------------------|------------------------------|---------------------------|
| 10,000               | ~$200/mo               | ~$210/mo            | ~$150/mo                     | ~$600                     |
| 50,000               | ~$1,000/mo             | ~$770/mo            | ~$150/mo                     | ~$10,200                  |
| 100,000              | ~$2,000/mo             | ~$1,470/mo          | ~$180/mo                     | ~$21,840                  |
| 500,000              | ~$10,000/mo            | ~$7,070/mo          | ~$180/mo                     | ~$117,840                 |
| 1,000,000            | ~$18,000/mo            | ~$14,070/mo         | ~$250/mo                     | ~$213,000                 |

### Operational Savings

Beyond direct licensing costs:

**Reduced vendor management overhead.** No contract negotiations, no renewal surprises, no sales calls about upgrading tiers. Your identity infrastructure is as predictable as your database.

**Faster incident response.** When something breaks, you have full access to every log, every config, every database row. No waiting on vendor support tickets to diagnose issues in a black box.

**No migration risk.** Vendor lock-in creates hidden costs — the eventual cost of migrating away when pricing changes or the provider sunsets features. With open-source Ory, there is nothing to migrate away from.

**Developer velocity.** Custom authentication flows, consent screens, and admin tooling can be modified in hours, not weeks of back-and-forth with vendor support or professional services engagements.

---

## Feature Comparison

An honest, transparent comparison against the major identity platforms. Where competitors are stronger, we say so. The goal is to help you make an informed decision — not to oversell.

**Legend:** ✅ Full support | ⚠️ Partial / requires add-on | ❌ Not available

### Authentication

| Feature                                 | OlympusOSS Identity Platform | Ory Network       | Auth0               | Okta                 |
|-----------------------------------------|------------------------------|--------------------|---------------------|----------------------|
| **Email + Password**                    | ✅                           | ✅                 | ✅                  | ✅                   |
| **Social Login (Google, GitHub, etc.)** | ✅ OIDC providers            | ✅ 15+ providers   | ✅ 30+ providers    | ✅ Extensive catalog |
| **Passwordless / Passkeys**             | ✅                           | ✅                 | ✅                  | ✅                   |
| **MFA / TOTP**                          | ✅                           | ✅                 | ✅                  | ✅                   |
| **Adaptive / Risk-Based MFA**           | ⚠️ In development           | ✅ Step-up MFA     | ✅ Built-in         | ✅ Built-in          |
| **Magic Links**                         | ✅                           | ✅                 | ✅                  | ⚠️ Limited           |
| **SMS OTP**                             | ⚠️ In development           | ✅ Built-in        | ✅ Built-in         | ✅ Built-in          |
| **WebAuthn / FIDO2**                    | ✅                           | ✅                 | ✅                  | ✅                   |
| **Backup / Recovery Codes**             | ✅                           | ✅ Lookup Secrets  | ✅                  | ✅                   |
| **Biometric Auth**                      | ✅ Via passkeys              | ✅ Via WebAuthn    | ✅ Via Guardian app | ✅ Via Okta Verify   |

### Federation & Enterprise SSO

| Feature                            | OlympusOSS Identity Platform | Ory Network                 | Auth0        | Okta                       |
|------------------------------------|------------------------------|-----------------------------|--------------|-----------------------------|
| **OIDC Federation**                | ✅                           | ✅                          | ✅           | ✅                          |
| **Enterprise SSO (OIDC — modern)** | ✅ Via Ory Hydra             | ✅ Via Ory Polis            | ✅           | ✅ Industry-leading         |
| **SAML 2.0 (legacy)**             | ⚠️ In development           | ✅ Via Ory Polis            | ✅           | ✅                          |
| **Directory Sync (AD/LDAP)**       | ⚠️ In development           | ⚠️ SCIM-based via Polis    | ✅           | ✅ Native AD agent          |
| **SCIM Provisioning**              | ⚠️ In development           | ✅ Via Ory Polis            | ✅           | ✅ 7000+ app integrations   |
| **User Lifecycle Management**      | ⚠️ In development           | ✅ Via SCIM + webhooks      | ✅           | ✅ Best-in-class            |
| **Pre-built App Integrations**     | ❌                           | ⚠️ Via Zapier (5000+ apps) | ✅ Extensive | ✅ 7000+ OIN catalog        |

### OAuth2 & Authorization

| Feature                       | OlympusOSS Identity Platform | Ory Network                   | Auth0                      | Okta                     |
|-------------------------------|------------------------------|-------------------------------|----------------------------|--------------------------|
| **Full OAuth2 Server**        | ✅ Ory Hydra (certified)     | ✅ Ory Hydra (certified)      | ✅                         | ✅                       |
| **OpenID Connect Provider**   | ✅                           | ✅ OpenID Certified            | ✅                         | ✅                       |
| **Custom Scopes & Claims**    | ✅ Full control              | ✅ Full control                | ✅                         | ✅                       |
| **Client Credentials Flow**   | ✅                           | ✅                             | ✅                         | ✅                       |
| **Device Authorization Flow** | ✅                           | ✅                             | ✅                         | ✅                       |
| **Token Introspection**       | ✅                           | ✅                             | ✅                         | ✅                       |
| **Custom Consent Screens**    | ✅ Medusa (full control)     | ✅ Headless (bring your own)   | ⚠️ Limited customization   | ⚠️ Limited customization |
| **Unlimited OAuth2 Clients**  | ✅                           | ✅                             | ⚠️ Tier-limited            | ⚠️ Tier-limited          |
| **Permissions (Zanzibar)**    | ❌                           | ✅ Ory Keto (OPL)             | ❌                         | ❌                       |

### Admin & Management

| Feature                     | OlympusOSS Identity Platform | Ory Network                            | Auth0                        | Okta                         |
|-----------------------------|------------------------------|----------------------------------------|------------------------------|------------------------------|
| **Admin Dashboard**         | ✅ Athena (custom-built)     | ✅ Ory Console                         | ✅ Polished SaaS dashboard   | ✅ Polished SaaS dashboard   |
| **Identity CRUD API**       | ✅ Full REST API             | ✅ Full REST API                       | ✅ Management API            | ✅                           |
| **Session Management**      | ✅ View + revoke             | ✅ View + revoke + extend              | ✅                           | ✅                           |
| **Custom Identity Schemas** | ✅ JSON Schema-based         | ✅ JSON Schema-based                   | ⚠️ Custom attributes         | ⚠️ Profile attributes        |
| **Audit Logging**           | ⚠️ In development           | ✅ Event streaming (Enterprise)        | ✅ Log streaming             | ✅ System Log + SIEM         |
| **User Migration Tools**    | ⚠️ In development           | ✅ Import API (passwords, social, MFA) | ✅ Automatic migration       | ✅ Import tools              |
| **Bulk User Import**        | ⚠️ In development           | ✅ Up to 1000/batch                    | ✅                           | ✅ CSV + API                 |

### Developer Experience

| Feature                    | OlympusOSS Identity Platform | Ory Network                                       | Auth0                              | Okta                          |
|----------------------------|------------------------------|---------------------------------------------------|------------------------------------|-------------------------------|
| **Self-Hosted Option**     | ✅ Full control              | ✅ Enterprise License available                    | ❌ SaaS only                       | ❌ SaaS only                  |
| **Open Source**            | ✅ Apache 2.0               | ✅ Apache 2.0 (core components)                    | ❌                                 | ❌                            |
| **SDK / Language Support** | ✅ REST API (any language)   | ✅ SDKs for Go, JS, PHP, Java, .NET, Python, Dart | ✅ SDKs for 15+ languages          | ✅ SDKs for 10+ languages    |
| **Pre-Built Login UI**     | ✅ Hera (custom-built)       | ✅ Ory Elements (React components)                 | ✅ Universal Login (best-in-class) | ✅ Sign-In Widget             |
| **UI Customization Depth** | ✅ Full source code control  | ✅ Full source code control (headless)             | ⚠️ Theming + Actions               | ⚠️ Theming + hooks            |
| **Documentation Quality**  | ⚠️ Good (Ory docs)          | ✅ Comprehensive                                   | ✅ Excellent                       | ✅ Excellent                  |
| **Extensibility / Hooks**  | ✅ Webhooks + custom code    | ✅ Ory Actions (any language)                      | ✅ Actions, Rules, Hooks           | ✅ Event Hooks, Inline Hooks  |
| **Community / Ecosystem**  | ⚠️ Growing (Ory community)  | ✅ Active Slack + GitHub community                 | ✅ Large, mature                   | ✅ Large, enterprise-focused  |
| **Time to First Auth**     | ⚠️ Hours (Docker setup)     | ✅ Minutes (SaaS + free tier)                      | ✅ Minutes (SaaS)                  | ✅ Minutes (SaaS)             |

### Infrastructure & Operations

| Feature                       | OlympusOSS Identity Platform | Ory Network                                          | Auth0                  | Okta                                   |
|-------------------------------|------------------------------|------------------------------------------------------|------------------------|----------------------------------------|
| **Full Data Ownership**       | ✅ Your database             | ⚠️ Ory-hosted (data residency options)               | ❌ Vendor-hosted       | ❌ Vendor-hosted                       |
| **Multi-Tenancy**             | ❌                           | ✅ Enterprise tier                                    | ✅                     | ✅                                     |
| **Built-in CIAM + IAM Split** | ✅ Core architecture         | ⚠️ Separate projects                                 | ❌ Separate tenants    | ⚠️ Separate products (CIC + WIC)      |
| **Cloud-Agnostic**            | ✅ Runs anywhere             | ⚠️ GCP-hosted (self-hosted enterprise available)     | ❌ Auth0 cloud         | ❌ Okta cloud                          |
| **Managed Service Option**    | ❌ Self-hosted only          | ✅ Fully managed                                      | ✅ Fully managed       | ✅ Fully managed                       |
| **SLA Guarantee**             | ❌ Self-managed              | ✅ 99.99% (Enterprise)                                | ✅ 99.99% (enterprise) | ✅ 99.99%                              |
| **Uptime Responsibility**     | ⚠️ Your ops team            | ✅ Ory-managed                                        | ✅ Vendor-managed      | ✅ Vendor-managed                      |

### Compliance & Security

| Feature                      | OlympusOSS Identity Platform                     | Ory Network                          | Auth0                            | Okta               |
|------------------------------|---------------------------------------------------|--------------------------------------|----------------------------------|--------------------|
| **SOC 2 Certified**          | ⚠️ Accelerated — built on Ory's audited codebase | ✅ SOC 2 Type II                     | ✅                               | ✅                 |
| **HIPAA Eligible**           | ⚠️ Accelerated — built on Ory's audited codebase | ⚠️ Contact sales                    | ✅ Enterprise tier               | ✅                 |
| **GDPR Ready**               | ✅ Full data control                              | ✅ EU data residency                 | ✅                               | ✅                 |
| **Brute Force Protection**   | ⚠️ Via rate limiting config                       | ✅ Built-in                          | ✅ Built-in                      | ✅ Built-in        |
| **Bot Detection**            | ⚠️ In development (CAPTCHA)                      | ✅ Cloudflare WAF + Bot Management   | ✅ Built-in                      | ✅ Built-in        |
| **Anomaly Detection**        | ❌                                                | ⚠️ Risk-based MFA                   | ✅ Breached password detection   | ✅ ThreatInsight   |
| **Pwned Password Detection** | ❌                                                | ✅ Built-in                          | ✅                               | ✅                 |
| **Rate Limiting**            | ✅ Configurable                                   | ✅ Tiered by plan                    | ✅                               | ✅                 |

### Where They Win

**Ory Network** is the closest comparison — it runs the exact same open-source components (Kratos + Hydra) that OlympusOSS Identity Platform is built on, but as a fully managed service. If you want the same Ory foundation without the operational overhead of self-hosting, Ory Network is the natural choice. They add enterprise features like Ory Polis (SAML/SCIM), Ory Keto (permissions), managed infrastructure with 99.99% SLA, SOC 2 Type II certification, and a generous free Developer tier. The tradeoff is per-aDAU pricing and less control over the infrastructure layer.

**Auth0** is the gold standard for developer experience. If your priority is getting authentication working in minutes with minimal code, Auth0 is hard to beat. Their Universal Login, pre-built SDKs for every language, and Actions extensibility system are best-in-class. Documentation is exceptional. For teams that want to move fast and don't mind per-user pricing, Auth0 is a strong choice.

**Okta** dominates workforce identity. If you need to provision employees across 7,000+ SaaS applications with SCIM, sync with Active Directory, and manage the full user lifecycle from onboarding to offboarding, Okta's Workforce Identity Cloud is unmatched. Their app integration catalog is the largest in the industry. For enterprises already invested in Okta's ecosystem, the operational maturity is a real advantage.

### Where OlympusOSS Identity Platform Wins

**Total cost of ownership at scale.** Every managed provider charges per user — including Ory Network. At 100K+ MAU, those costs reach tens of thousands per month. OlympusOSS Identity Platform's cost is fixed infrastructure — the same whether you have 1,000 users or 10 million.

**Full OAuth2 server included.** Most identity providers are authentication services. OlympusOSS Identity Platform includes Ory Hydra — a certified, full-featured OAuth2 and OpenID Connect server. Auth0 and Okta charge extra for comparable OAuth2 server capabilities.

**Data sovereignty.** Your identity data lives in your database, in your infrastructure, in your region. No vendor has access. No data processing agreements needed. No compliance questions about where customer PII is stored.

**CIAM + IAM as a unified architecture.** Most providers treat customer identity and workforce identity as separate products with separate billing. Okta literally sells them as two different clouds (Customer Identity Cloud + Workforce Identity Cloud). OlympusOSS Identity Platform provides both in a single, integrated architecture at no additional cost.

**Complete UI ownership.** Managed providers give you theming controls. OlympusOSS Identity Platform gives you the full source code for the admin panel (Athena), consent UI (Medusa), and authentication UI (Hera). Every pixel, every flow, every interaction is yours to modify.

**No vendor lock-in.** Built on open-source Ory (Apache 2.0). No proprietary APIs, no contracts, no renewal negotiations. If you decide to change approaches, your data is already in PostgreSQL — there's nothing to export or migrate.

---

## Port Allocation

| Port | Service               | Domain   | Purpose                                      |
|------|-----------------------|----------|----------------------------------------------|
| 2000 | Demo App              | —        | OAuth2 test client for both domains          |
| 3001 | CIAM Hera             | Customer | Authentication UI for customers              |
| 3002 | CIAM Medusa           | Customer | OAuth2 consent for customer-facing apps      |
| 3003 | CIAM Athena           | Customer | Admin panel for customer identity management |
| 3100 | CIAM Kratos (public)  | Customer | Customer identity API                        |
| 3101 | CIAM Kratos (admin)   | Customer | Customer identity admin API                  |
| 3102 | CIAM Hydra (public)   | Customer | Customer OAuth2/OIDC endpoints               |
| 3103 | CIAM Hydra (admin)    | Customer | Customer OAuth2 admin API                    |
| 4001 | IAM Hera              | Employee | Authentication UI for employees              |
| 4002 | IAM Medusa            | Employee | OAuth2 consent for internal services         |
| 4003 | IAM Athena            | Employee | Employee identity management                 |
| 4100 | IAM Kratos (public)   | Employee | Employee identity API                        |
| 4101 | IAM Kratos (admin)    | Employee | Employee identity admin API                  |
| 4102 | IAM Hydra (public)    | Employee | Internal OAuth2/OIDC endpoints               |
| 4103 | IAM Hydra (admin)     | Employee | Internal OAuth2 admin API                    |

---

## Technology

| Component           | Technology                                             |
|---------------------|--------------------------------------------------------|
| Identity Management | [Ory Kratos](https://www.ory.sh/kratos/)               |
| OAuth2 / OIDC       | [Ory Hydra](https://www.ory.sh/hydra/)                 |
| Admin Interface     | [Athena](./Athena) — Next.js, TypeScript, Material UI  |
| Consent UI          | [Medusa](./Medusa) — Next.js, TypeScript               |
| Authentication UI   | [Hera](./Hera) — Next.js, TypeScript                   |
| Demo App            | [Demo](./Demo) — Next.js, TypeScript                   |
| Runtime             | [Bun](https://bun.sh/)                                 |
| Database            | PostgreSQL                                             |
| Containerization    | Docker / Docker Compose                                |

---

## Acknowledgments

Athena was originally forked from [dhia-gharsallaoui/kratos-admin-ui](https://github.com/dhia-gharsallaoui/kratos-admin-ui). The project has since been significantly extended with Hydra OAuth2 management, dual CIAM/IAM architecture, and a complete UI redesign — but the original work provided a valuable foundation.
