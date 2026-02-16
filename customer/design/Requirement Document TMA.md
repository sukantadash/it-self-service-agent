Requirement Document: Type-A Migration Agent (TMA)
=================================================

1. Project Overview
------------------

This document defines the functional requirements and state machine configuration for an agentic AI system assisting with application migrations. It utilizes a hierarchical model where a central Routing Agent (Rachel) delegates tasks to a Type-A Migration Agent (TMA).

2. High-Level Design Flow
-------------------------

### 2.1 End-to-End System Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          SESSION MANAGER                                │
│  Manages user sessions, detects routing_decision / _should_return_to_  │
│  routing flags, and hands off between agents.                          │
└────────────┬───────────────────────────────────────┬────────────────────┘
             │                                       │
             ▼                                       ▼
┌────────────────────────┐              ┌─────────────────────────────────┐
│    ROUTING AGENT       │  routes to   │   TYPE-A MIGRATION AGENT (TMA) │
│    (Rachel)            │─────────────▶│                                 │
│                        │              │   App Lookup → Discovery        │
│  routing.yaml          │◀─────────────│   lg-prompt-type-a-migration-  │
│                        │  returns via │   smaller.yaml                  │
│                        │  _should_    │                                 │
│                        │  return_to_  │                                 │
│                        │  routing     │                                 │
└────────────────────────┘              └─────────────────────────────────┘
```

### 2.2 Routing Agent Flow Diagram

```
                         ┌──────────────────────────┐
                         │  R1: greet_and_identify_  │
                         │       need                │
                         │  (llm_processor)          │
                         │  "Hello! I can help with  │
                         │   Type-A app migration."  │
                         └────────────┬──────────────┘
                                      │ success
                                      ▼
                         ┌──────────────────────────┐
                         │  R2: waiting_user_need    │◀─────────────────┐
                         │  (waiting)                │                  │
                         └────────────┬──────────────┘                  │
                                      │ user_input                     │
                                      ▼                                │
                         ┌──────────────────────────┐                  │
                         │  R3: classify_user_intent │                  │
                         │  (intent_classifier)      │          failure │
                         │                           │─────────────────┘
                         │  TYPE_A_MIGRATION / OTHER │
                         └──────┬─────────┬──────────┘
                   TYPE_A_      │         │  OTHER
                   MIGRATION    │         │
                                ▼         ▼
       ┌───────────────────┐   ┌──────────────────────────┐
       │  R6: end           │   │  R4: handle_other_request│
       │  (terminal)        │   │  (llm_processor)         │
       │                    │   │  "We can help with       │
       │  routing_decision  │   │   Type-A migration..."   │
       │  = type-a-app-     │   └────────────┬─────────────┘
       │    migration       │                │ success
       │                    │                ▼
       │  → Session Manager │   ┌──────────────────────────┐
       │    routes to TMA   │   │  R5: waiting_clarification│
       └───────────────────┘   │  (waiting)                │
                                └────────────┬─────────────┘
                                             │ user_input
                                             │
                                             └──▶ R3 (re-classify)
```

### 2.3 Type-A Migration Agent (TMA) — Complete Flow Diagram

```
════════════════════════════════════════════════════════════════════════════
 PHASE 1: APP IDENTIFICATION
════════════════════════════════════════════════════════════════════════════

   User message arrives (from Routing Agent or loop-back)
                         │
                         ▼
          ┌───────────────────────────────┐
          │  S1: derive_app_search_q      │
          │  (llm_processor, T=0.1)       │
          │                               │
          │  Extract app name/ID/namespace│
          │  from user message.           │
          │  Strips action verbs:         │
          │  "migrate payments" → "Q:     │
          │   payments"                   │
          └──────┬──────────┬─────────────┘
        Q: NONE  │          │  Q: <value>
        (generic)│          │  (specific)
                 │          │
                 │          │  extract_data → app_search_q
                 │          ▼
                 │   ┌──────────────────────────────────┐
                 │   │  S2: search_app_catalog_normalize │
                 │   │  (llm_processor, T=0.2)           │
                 │   │                                    │
                 │   │  Tool: search_app_catalog           │
                 │   │  q = {app_search_q}                │
                 │   │  → CANDIDATES: 1) ... 2) ...       │
                 │   │  → CANDIDATES: NONE                │
                 │   │                                    │
                 │   │  failure_transition → S4           │
                 │   └──────────────┬─────────────────────┘
                 │                  │ success
                 │                  ▼
                 │   ┌──────────────────────────────────┐
                 │   │  S3: format_lookup_status         │
                 │   │  (llm_processor, T=0.1)           │
                 │   │                                    │
                 │   │  Present results to user:          │
                 │   │  0 matches → "I couldn't find..."  │
                 │   │  1 match   → "I've located X..."   │
                 │   │  N matches → "Multiple matches..." │
                 │   └──┬────────────┬────────────┬───────┘
                 │      │            │            │
                 │  0 matches    1 match     N matches
                 │      │            │            │
                 ▼      ▼            │            ▼
    ┌─────────────────────────┐      │   ┌────────────────────────┐
    │  S4: waiting_app_query  │◀─────┘   │  S6: waiting_app_      │
    │  (waiting)              │          │       selection         │
    └────────────┬────────────┘          │  (waiting)             │
                 │ user_input            └──────────┬─────────────┘
                 ▼                                  │ user_input
    ┌─────────────────────────┐                     ▼
    │  S5: classify_app_query │         ┌───────────────────────────┐
    │       _intent           │         │  S7: classify_app_        │
    │  (intent_classifier)    │         │       selection           │
    │                         │         │  (intent_classifier)      │
    │  QUERY / RETURN_TO_     │         │                           │
    │  ROUTER / SWITCH_TASK / │         │  VALID_SELECTION /        │
    │  UNCLEAR                │         │  INVALID_SELECTION /      │
    └──┬──┬──────┬────────┬───┘         │  RETRY_LOOKUP /          │
       │  │      │        │             │  RETURN_TO_ROUTER        │
  QUERY│  │RTR/  │UNCLEAR │             └──┬──┬──────┬─────┬───────┘
       │  │SWITCH│        │                │  │      │     │
       │  │      │        │    VALID_      │  │RETRY │RTR  │INVALID
       │  │      ▼        │    SELECTION   │  │      │     │
       │  │  S4 (loop)    │               │  │      │     │
       │  │               │               ▼  │      │     ▼
       │  │               │  ┌──────────────┐│      │  S6 (loop)
       │  ▼               │  │S8: resolve_  ││      │
       │  S15: end ◀──────┘  │app_selection ││      │
       │  (terminal,         │(llm_processor)│      │
       │  _should_return_    │              ││      │
       │  to_routing=true)   │UNIQUE → S4a  ││      │
       │                     │ERROR → S6    ││      │
       ▼                     └──────┬───────┘│      │
    S1 (re-derive)                  │        │      ▼
                                    │        │   S15: end
                                    │        │
                                    ▼        ▼
                               S4: waiting   S4: waiting_app_query
                               _discovery_
                               confirmation

════════════════════════════════════════════════════════════════════════════
 PHASE 2: DISCOVERY CONFIRMATION
════════════════════════════════════════════════════════════════════════════

    (from S3-unique or S8-unique)
                 │
                 ▼
    ┌────────────────────────────────┐
    │  S4a: waiting_discovery_       │
    │        confirmation            │◀──── UNCLEAR (loop)
    │  (waiting)                     │
    └────────────┬───────────────────┘
                 │ user_input
                 ▼
    ┌────────────────────────────────┐
    │  S4b: classify_discovery_      │
    │        confirmation            │
    │  (intent_classifier)           │
    │                                │
    │  YES / NO / RETURN_TO_ROUTER / │
    │  UNCLEAR                       │
    └──┬─────┬──────┬────────┬───────┘
       │     │      │        │
      YES   NO     RTR    UNCLEAR
       │     │      │        │
       │     │      │        └──▶ S4a (loop with clarification)
       │     │      │
       │     │      ▼
       │     │   S15: end (_should_return_to_routing=true)
       │     │
       │     ▼
       │  S4: waiting_app_query (new search)
       │
       ▼

════════════════════════════════════════════════════════════════════════════
 PHASE 3: RESOURCE DISCOVERY PIPELINE
════════════════════════════════════════════════════════════════════════════

       │ (YES from confirmation)
       ▼
    ┌────────────────────────────────┐
    │  S10: discover_workloads       │
    │  (llm_processor, T=0.2)        │
    │                                │
    │  Tools: resources_list          │
    │  - Deployment, StatefulSet,    │
    │    DaemonSet                   │
    │  → discovery_workloads         │
    └────────────┬───────────────────┘
                 │ success
                 ▼
    ┌────────────────────────────────┐
    │  S11: discover_networking      │
    │  (llm_processor, T=0.2)        │
    │                                │
    │  Tools: resources_list          │
    │  - Service, Route, Ingress     │
    │  → discovery_network           │
    └────────────┬───────────────────┘
                 │ success
                 ▼
    ┌────────────────────────────────┐
    │  S12: discover_storage         │
    │  (llm_processor, T=0.2)        │
    │                                │
    │  Tools: resources_list          │
    │  - PersistentVolumeClaim       │
    │  → discovery_storage           │
    └────────────┬───────────────────┘
                 │ success
                 ▼
    ┌────────────────────────────────┐
    │  S13: summarize_discovery      │
    │  (llm_processor, T=0.2)        │
    │                                │
    │  Presents discovery summary    │
    │  to user with app context.     │
    │  "Do you want to look up       │
    │   another app, re-run          │
    │   discovery, or return?"       │
    └────────────┬───────────────────┘
                 │ success
                 ▼

════════════════════════════════════════════════════════════════════════════
 PHASE 4: POST-DISCOVERY DECISION
════════════════════════════════════════════════════════════════════════════

    ┌────────────────────────────────┐
    │  S9: waiting_post_discovery    │◀──── UNCLEAR (loop)
    │  (waiting)                     │
    └────────────┬───────────────────┘
                 │ user_input
                 ▼
    ┌────────────────────────────────┐
    │  S14: classify_post_discovery_ │
    │        intent                  │
    │  (intent_classifier)           │
    │                                │
    │  ANOTHER_APP / REDISCOVER /    │
    │  RETURN_TO_ROUTER / UNCLEAR    │
    └──┬─────────┬──────┬─────┬──────┘
       │         │      │     │
  ANOTHER_APP    │  REDISCOVER│ UNCLEAR
       │         │      │     │
       │         │      │     └──▶ S9 (loop with clarification)
       │         │      │
       │         │      └──▶ S10: discover_workloads (re-run)
       │         │
       │         ▼
       │      S15: end (_should_return_to_routing=true)
       │
       ▼
    S4: waiting_app_query (all fields cleared, fresh search)
```

3. Routing Agent Configuration
-----------------------------

### 3.1 Settings

```
initial_state: greet_and_identify_need
agent_name: routing-agent
terminal_state: end
empty_response_retry_count: 5
```

### 3.2 State Schema

```
business_fields:
  routing_decision: String (default: null)
    — Stores the target agent name for the session manager to detect
```

### 3.3 State Definitions

**R1: greet_and_identify_need** — `llm_processor` (T=0.3)

Greets the user and lists available services. Currently supports:
- Type-A application migration (OVA → OpenShift Virtualization using MTV)

Transitions: success → R2 `waiting_user_need`

---

**R2: waiting_user_need** — `waiting`

Transitions: user_input → R3 `classify_user_intent`

---

**R3: classify_user_intent** — `intent_classifier` (T=0.1)

Classifies user input into:
- `TYPE_A_MIGRATION` → Sets `routing_decision = "type-a-app-migration"` → R6 `end`
- `OTHER` → R4 `handle_other_request`

Failure transition → R2 `waiting_user_need`

---

**R4: handle_other_request** — `llm_processor` (T=0.3)

Explains that only Type-A application migration is available. Asks user to clarify.

Transitions: success → R5 `waiting_clarification`

---

**R5: waiting_clarification** — `waiting`

Transitions: user_input → R3 `classify_user_intent` (re-classify)

---

**R6: end** — `terminal`

Session manager detects `routing_decision` field and routes to the target specialist agent.

4. Type-A Migration Agent (TMA) Configuration
----------------------------------------------

### 4.1 Settings

```
initial_state: State 1: derive_app_search_q
agent_name: type-a-app-migration
terminal_state: State 15: end
empty_response_retry_count: 3
terminator_env_var: AGENT_MESSAGE_TERMINATOR
```

### 4.2 State Schema (Data Storage)

```
business_fields:
  app_id: String (Unique identifier)
  app_name: String (Display name)
  namespace: String (K8s project)
  source_cluster: String
  destination_cluster: String
  app_search_q: String (The extracted search substring)
  app_catalog_candidates: Dict (Raw results from tool call)
  app_lookup_results: Dict (The formatted prompt for selection)
  selected_app_choice: String (User's selection when multiple matches)
  discovery_workloads: Dict (Extracted K8s workload names)
  discovery_network: Dict (Services/Routes)
  discovery_storage: Dict (PVCs)
  _should_return_to_routing: Boolean (Flag for session manager)
```

### 4.3 State Definitions

**State 1: derive_app_search_q** — `llm_processor` (T=0.1)

Extracts the specific application name, ID, or namespace from the user message. Strips action verbs (e.g., "migrate payments" → `Q: payments`). Generic messages produce `Q: NONE`.

Response Analysis:
- `Q: NONE` → add_message (prompt for app name) → State 4 `waiting_app_query`
- `Q: <value>` → extract_data to `app_search_q` → State 2

---

**State 2: search_app_catalog_normalize** — `llm_processor` (T=0.2)

Tool: `search_app_catalog` with `q = {app_search_q}`, `limit=50`, `offset=0`.

Outputs normalized candidate list or `CANDIDATES: NONE`.

Data Storage: `app_catalog_candidates = llm_response`

Transitions: success → State 3. Failure → State 4 `waiting_app_query`.

---

**State 3: format_lookup_status** — `llm_processor` (T=0.1)

Presents catalog results conversationally:
- 0 matches → "I couldn't find any matching apps..." → State 4
- 1 match → "I've located X (ID: Y) in namespace Z..." + extract_data → State 4a `waiting_discovery_confirmation`
- N matches → "I found multiple matches..." → State 6 `waiting_app_selection`

Data Storage: `app_lookup_results = llm_response`

---

**State 4: waiting_app_query** — `waiting`

Transitions: user_input → State 5

---

**State 5: classify_app_query_intent** — `intent_classifier` (T=0.2)

Intent Actions:
- `QUERY` → State 1 `derive_app_search_q`
- `RETURN_TO_ROUTER` / `SWITCH_TASK` → Set `_should_return_to_routing = true` → State 15
- `UNCLEAR` → Clarification prompt → State 4

---

**State 4a: waiting_discovery_confirmation** — `waiting`

Transitions: user_input → State 4b

---

**State 4b: classify_discovery_confirmation** — `intent_classifier` (T=0.2)

Intent Actions:
- `YES` → State 10 `discover_workloads`
- `NO` → Prompt for new search → State 4 `waiting_app_query`
- `RETURN_TO_ROUTER` → Set `_should_return_to_routing = true` → State 15
- `UNCLEAR` → Clarification → State 4a (loop)

---

**State 6: waiting_app_selection** — `waiting`

Transitions: user_input → State 7

---

**State 7: classify_app_selection** — `intent_classifier` (T=0.2)

Intent Actions:
- `VALID_SELECTION` → Store `selected_app_choice` → State 8
- `INVALID_SELECTION` → Error message → State 6 (loop)
- `RETRY_LOOKUP` → State 4 `waiting_app_query`
- `RETURN_TO_ROUTER` → Set `_should_return_to_routing = true` → State 15

---

**State 8: resolve_app_selection** — `llm_processor` (T=0.2)

Resolves user choice to one option. On success, extract_data captures metadata → State 4a. On error → State 6.

---

**State 9: waiting_post_discovery** — `waiting`

Transitions: user_input → State 14

---

**State 10: discover_workloads** — `llm_processor` (T=0.2)

Tools: `resources_list` for Deployments, StatefulSets, DaemonSets in `{namespace}`.

Data Storage: `discovery_workloads = llm_response`

Transitions: success → State 11

---

**State 11: discover_networking** — `llm_processor` (T=0.2)

Tools: `resources_list` for Services, Routes, Ingresses in `{namespace}`.

Data Storage: `discovery_network = llm_response`

Transitions: success → State 12

---

**State 12: discover_storage** — `llm_processor` (T=0.2)

Tools: `resources_list` for PVCs in `{namespace}`.

Data Storage: `discovery_storage = llm_response`

Transitions: success → State 13

---

**State 13: summarize_discovery** — `llm_processor` (T=0.2)

Summarizes workloads, networking, and storage conversationally. Asks user what to do next.

Transitions: success → State 9

---

**State 14: classify_post_discovery_intent** — `intent_classifier` (T=0.2)

Intent Actions:
- `ANOTHER_APP` → Clear all business fields → State 4
- `REDISCOVER` → State 10 (re-run with same namespace)
- `RETURN_TO_ROUTER` → Set `_should_return_to_routing = true` → State 15
- `UNCLEAR` → Clarification → State 9 (loop)

---

**State 15: end** — `terminal`

Reset Behavior: Clears all business fields and retry counters (except `_should_return_to_routing`, which persists for session manager detection).

5. Test Cases
-------------

All test cases begin from the Routing Agent entry point and trace through to the TMA states.

### TC-R01: Routing — Direct TYPE_A_MIGRATION classification

```
Precondition: New session
User: "I want to migrate an application"
  → R1: greet_and_identify_need → greeting shown
  → R2: waiting_user_need (pause)
  → R3: classify_user_intent → TYPE_A_MIGRATION
  → R6: end (routing_decision = "type-a-app-migration")
  → Session Manager routes to TMA
  → S1: derive_app_search_q (Q: NONE) → "Please provide the Application Name..."
Expected: User is greeted, classified as TYPE_A_MIGRATION, and handed off to TMA.
```

### TC-R02: Routing — OTHER classification → clarification → TYPE_A_MIGRATION

```
Precondition: New session
User: "help me please"
  → R1: greet_and_identify_need → greeting shown
  → R2: waiting_user_need (pause)
  → R3: classify_user_intent → OTHER
  → R4: handle_other_request → "We can help with Type-A migration..."
  → R5: waiting_clarification (pause)
User: "I need to migrate my app"
  → R3: classify_user_intent → TYPE_A_MIGRATION
  → R6: end (routing_decision = "type-a-app-migration")
  → Session Manager routes to TMA
Expected: User's unclear request is clarified, then correctly routed.
```

### TC-R03: Routing — "migrate payments" correctly classified as TYPE_A_MIGRATION

```
Precondition: New session
User: "migrate payments"
  → R3: classify_user_intent → TYPE_A_MIGRATION
  → R6: end (routing_decision = "type-a-app-migration")
  → Session Manager routes to TMA
  → S1: derive_app_search_q (Q: payments) → S2 → S3 → ...
Expected: "migrate <app>" pattern is correctly classified. Verb "migrate" stripped by S1.
```

### TC-001: Full E2E happy path — vague entry → prompt → unique match → confirm → discovery → return

```
Precondition: Routing agent has classified TYPE_A_MIGRATION; TMA starts.
Turn 1 — User: "I want to migrate an application"
  State flow: S1 derive_app_search_q (Q: NONE) → S4 waiting_app_query
  Logic: Generic message → Q: NONE; add_message fires; system pauses
  Response: "I can help you with your migration. To get started, please provide
            the Application Name, App ID, or its Namespace."

Turn 2 — User: "oom-test-app"
  State flow: S5 classify_app_query_intent (QUERY) → S1 derive_app_search_q
              (Q: oom-test-app) → S2 search_app_catalog_normalize
              → S3 format_lookup_status (UNIQUE) → S4a waiting_discovery_confirmation
  Logic: Intent=QUERY; search term extracted; tool called; 1 candidate;
         extract_data captures app_name, app_id, namespace
  Response: "I've located out memory app (ID: oom-test-app) in namespace oom-test.
            Should I proceed with the resource discovery for this application?"

Turn 3 — User: "yes, go ahead"
  State flow: S4b classify_discovery_confirmation (YES) → S10 discover_workloads
              → S11 discover_networking → S12 discover_storage
              → S13 summarize_discovery → S9 waiting_post_discovery
  Logic: Intent=YES; resources_list MCP tool called for all resource types;
         results summarized conversationally
  Response: "[Discovery summary for oom-test]. Do you want to look up another app,
            re-run discovery, or return to the main menu?"

Turn 4 — User: "that's all, thanks"
  State flow: S14 classify_post_discovery_intent (RETURN_TO_ROUTER) → S15 end
  Logic: Intent=RETURN_TO_ROUTER; _should_return_to_routing=true; terminal state
  Response: task_complete_return_to_router
```

### TC-002: Disambiguation flow — multiple matches → selection by number → confirm → discovery

```
Turn 1 — User: "migrate payments"
  State flow: S1 (Q: payments) → S2 → S3 format_lookup_status (MULTIPLE)
              → S6 waiting_app_selection
  Logic: LLM extracts "payments"; search returns 2+ candidates; multiple match
  Response: "I found multiple matches... 1) payments-api 2) legacy-pay ...
            Please reply with the number or App ID."

Turn 2 — User: "1"
  State flow: S7 classify_app_selection (VALID_SELECTION)
              → S8 resolve_app_selection (UNIQUE) → S4a waiting_discovery_confirmation
  Logic: selected_app_choice="1"; resolved to payments-api; extract_data fires
  Response: "I've located payments-api (ID: payments-api) in namespace payments.
            Should I proceed with the resource discovery?"

Turn 3 — User: "yes"
  State flow: S4b (YES) → S10 → S11 → S12 → S13 → S9
  Logic: Discovery pipeline for namespace "payments"
  Response: "[Discovery summary]. Do you want to look up another app, re-run
            discovery, or return to the main menu?"
```

### TC-003: Direct app name → confirm → full discovery

```
Turn 1 — User: "I need help with hello-world"
  State flow: S1 (Q: hello-world) → S2 → S3 (UNIQUE)
              → S4a waiting_discovery_confirmation
  Logic: 1 candidate; extract_data captures app fields
  Response: "I've located hello-world (ID: hello-world) in namespace default.
            Should I proceed with the resource discovery?"

Turn 2 — User: "Yes, please proceed"
  State flow: S4b (YES) → S10 → S11 → S12 → S13 → S9
  Logic: Full discovery pipeline for namespace "default"
  Response: "[Discovery summary]. Do you want to look up another app, re-run
            discovery, or return to the main menu?"
```

### TC-004: SWITCH_TASK — user changes topic while waiting for app query

```
Turn 1 — User: "migration help"
  State flow: S1 (Q: NONE) → S4 waiting_app_query
  Response: "Please provide the Application Name, App ID, or its Namespace."

Turn 2 — User: "Actually, I just need a laptop refresh"
  State flow: S5 classify_app_query_intent (SWITCH_TASK) → S15 end
  Logic: _should_return_to_routing=true
  Response: "No problem! I'll connect you back with the routing agent..."
```

### TC-005: Post-discovery rediscovery (REDISCOVER)

```
Precondition: At S9 waiting_post_discovery after completed discovery for hello-world.
Turn 1 — User: "please re-run the scan for the current app"
  State flow: S14 (REDISCOVER) → S10 → S11 → S12 → S13 → S9
  Logic: Same namespace reused; discovery pipeline re-executes
  Response: "Understood. Re-running... [Updated discovery summary]. Do you want to
            look up another app, re-run discovery, or return to the main menu?"
```

### TC-006: No matches → user retries with corrected query

```
Turn 1 — User: "migrate xyznonexistent"
  State flow: S1 (Q: xyznonexistent) → S2 → S3 (NONE) → S4 waiting_app_query
  Logic: 0 candidates; "I couldn't find" trigger fires
  Response: "I couldn't find any matching apps. Please provide the Application
            Name, App ID, or Namespace."

Turn 2 — User: "hello-world"
  State flow: S5 (QUERY) → S1 (Q: hello-world) → S2 → S3 (UNIQUE)
              → S4a waiting_discovery_confirmation
  Response: "I've located hello-world (ID: hello-world) in namespace default.
            Should I proceed?"
```

### TC-007: Invalid selection → error → valid selection

```
Turn 1 — User: "payments"
  State flow: S1 → S2 → S3 (MULTIPLE) → S6 waiting_app_selection
  Response: "I found multiple matches... 1) payments-api 2) legacy-pay ..."

Turn 2 — User: "99"
  State flow: S7 classify_app_selection (INVALID_SELECTION) → S6 (loop)
  Response: "I don't see that selection. Please reply with an option number or app_id."

Turn 3 — User: "2"
  State flow: S7 (VALID_SELECTION) → S8 (UNIQUE) → S4a
  Response: "I've located legacy-payments (ID: legacy-pay) in namespace payments-old.
            Should I proceed?"
```

### TC-008: Discovery confirmation declined (NO) → new search

```
Turn 1 — User: "oom-test-app"
  State flow: S1 → S2 → S3 (UNIQUE) → S4a
  Response: "I've located out memory app (ID: oom-test-app)... Should I proceed?"

Turn 2 — User: "no, wrong app"
  State flow: S4b (NO) → S4 waiting_app_query
  Response: "No problem. Please provide the next Application Name, App ID, or Namespace."

Turn 3 — User: "hello-world"
  State flow: S5 (QUERY) → S1 → S2 → S3 (UNIQUE) → S4a
  Response: "I've located hello-world (ID: hello-world) in namespace default.
            Should I proceed?"
```

### TC-009: UNCLEAR discovery confirmation → clarification → YES

```
Precondition: At S4a after locating an app.
Turn 1 — User: "hmm maybe"
  State flow: S4b (UNCLEAR) → S4a (loop)
  Response: "Please reply yes/no: should I proceed with the resource discovery?"

Turn 2 — User: "yes"
  State flow: S4b (YES) → S10 → S11 → S12 → S13 → S9
  Response: "[Discovery summary]. Do you want to look up another app, re-run
            discovery, or return to the main menu?"
```

### TC-010: Post-discovery — look up another app (ANOTHER_APP)

```
Precondition: At S9 after completed discovery for hello-world.
Turn 1 — User: "I want to look up a different app"
  State flow: S14 (ANOTHER_APP) → S4 waiting_app_query
  Logic: All business fields cleared to null; fresh search cycle
  Response: "Okay — please provide the next app name, app_id, or namespace."

Turn 2 — User: "oom-test-app"
  State flow: S5 (QUERY) → S1 → S2 → S3 (UNIQUE) → S4a
  Logic: New extract_data populates fresh fields
  Response: "I've located out memory app (ID: oom-test-app) in namespace oom-test.
            Should I proceed?"
```

### TC-011: Return to router from disambiguation

```
Turn 1 — User: "payments"
  State flow: S1 → S2 → S3 (MULTIPLE) → S6 waiting_app_selection
  Response: "I found multiple matches... 1) payments-api 2) legacy-pay ..."

Turn 2 — User: "cancel, go back"
  State flow: S7 (RETURN_TO_ROUTER) → S15 end
  Logic: _should_return_to_routing=true
  Response: task_complete_return_to_router
```

### TC-012: Return to router from discovery confirmation

```
Turn 1 — User: "hello-world"
  State flow: S1 → S2 → S3 (UNIQUE) → S4a
  Response: "I've located hello-world... Should I proceed?"

Turn 2 — User: "stop, return to router"
  State flow: S4b (RETURN_TO_ROUTER) → S15 end
  Logic: _should_return_to_routing=true
  Response: "No problem! I'll connect you back with the routing agent."
```

### TC-013: Selection by app_id string instead of number

```
Turn 1 — User: "payments"
  State flow: S1 → S2 → S3 (MULTIPLE) → S6
  Response: "I found multiple matches... 1) payments-api 2) legacy-pay ..."

Turn 2 — User: "legacy-pay"
  State flow: S7 (VALID_SELECTION) → S8 (UNIQUE) → S4a
  Logic: selected_app_choice="legacy-pay"; resolved by app_id match
  Response: "I've located legacy-payments (ID: legacy-pay) in namespace payments-old.
            Should I proceed?"
```

### TC-014: UNCLEAR query → clarification → valid query

```
Turn 1 — User: "help me migrate"
  State flow: S1 (Q: NONE) → S4 waiting_app_query
  Response: "Please provide the Application Name, App ID, or its Namespace."

Turn 2 — User: "uhhh"
  State flow: S5 (UNCLEAR) → S4 (loop)
  Response: "Please provide the app name, app_id, or namespace. Or say 'cancel'."

Turn 3 — User: "oom-test-app"
  State flow: S5 (QUERY) → S1 → S2 → S3 (UNIQUE) → S4a
  Response: "I've located out memory app (ID: oom-test-app) in namespace oom-test.
            Should I proceed?"
```

### TC-015: Disambiguation — RETRY_LOOKUP with new search term

```
Turn 1 — User: "payments"
  State flow: S1 → S2 → S3 (MULTIPLE) → S6
  Response: "I found multiple matches... 1) payments-api 2) legacy-pay ..."

Turn 2 — User: "none of these, let me search for something else"
  State flow: S7 (RETRY_LOOKUP) → S4 waiting_app_query
  Response: (system prompts for new query)

Turn 3 — User: "hello-world"
  State flow: S5 (QUERY) → S1 → S2 → S3 (UNIQUE) → S4a
  Response: "I've located hello-world (ID: hello-world) in namespace default.
            Should I proceed?"
```

### TC-016: Post-discovery UNCLEAR → clarification → RETURN_TO_ROUTER

```
Precondition: At S9 after completed discovery.
Turn 1 — User: "hmm not sure"
  State flow: S14 (UNCLEAR) → S9 (loop)
  Response: "Please reply with one of: another app / re-run discovery / return to router."

Turn 2 — User: "return to router"
  State flow: S14 (RETURN_TO_ROUTER) → S15 end
  Logic: _should_return_to_routing=true
  Response: task_complete_return_to_router
```

### TC-017: Explicit cancel from waiting_app_query

```
Turn 1 — User: "migration"
  State flow: S1 (Q: NONE) → S4 waiting_app_query
  Response: "Please provide the Application Name, App ID, or its Namespace."

Turn 2 — User: "cancel"
  State flow: S5 (RETURN_TO_ROUTER) → S15 end
  Logic: _should_return_to_routing=true
  Response: "No problem! I'll connect you back with the routing agent."
```

6. State Coverage Matrix
------------------------

| State | Type | Covered By |
|-------|------|------------|
| **Routing Agent** | | |
| R1 greet_and_identify_need | llm_processor | TC-R01, TC-R02 |
| R2 waiting_user_need | waiting | TC-R01, TC-R02 |
| R3 classify_user_intent | intent_classifier | TC-R01, TC-R02, TC-R03 |
| R4 handle_other_request | llm_processor | TC-R02 |
| R5 waiting_clarification | waiting | TC-R02 |
| R6 end | terminal | TC-R01, TC-R02, TC-R03 |
| **TMA** | | |
| S1 derive_app_search_q | llm_processor | TC-001–004, 006–008, 011, 013–015, 017 |
| S2 search_app_catalog_normalize | llm_processor | TC-001–003, 006–008, 011, 013–015 |
| S3 format_lookup_status | llm_processor | TC-001–003, 006–008, 011, 013–015 |
| S4 waiting_app_query | waiting | TC-001, 004, 006, 008, 010, 014–015, 017 |
| S4a waiting_discovery_confirmation | waiting | TC-001–003, 006–010, 012–014 |
| S4b classify_discovery_confirmation | intent_classifier | TC-001–003, 008, 009, 012 |
| S5 classify_app_query_intent | intent_classifier | TC-001, 004, 006, 008, 010, 014–015, 017 |
| S6 waiting_app_selection | waiting | TC-002, 007, 011, 013, 015 |
| S7 classify_app_selection | intent_classifier | TC-002, 007, 011, 013, 015 |
| S8 resolve_app_selection | llm_processor | TC-002, 007, 013 |
| S9 waiting_post_discovery | waiting | TC-001, 005, 010, 016 |
| S10 discover_workloads | llm_processor | TC-001–003, 005, 009 |
| S11 discover_networking | llm_processor | TC-001–003, 005, 009 |
| S12 discover_storage | llm_processor | TC-001–003, 005, 009 |
| S13 summarize_discovery | llm_processor | TC-001–003, 005, 009 |
| S14 classify_post_discovery_intent | intent_classifier | TC-001, 005, 010, 016 |
| S15 end | terminal | TC-001, 004, 011, 012, 016, 017 |

### Intent Action Coverage

| State | Intent | Covered By |
|-------|--------|------------|
| R3 classify_user_intent | TYPE_A_MIGRATION | TC-R01, TC-R03 |
| R3 classify_user_intent | OTHER | TC-R02 |
| S4b classify_discovery_confirmation | YES | TC-001, 002, 003, 009 |
| S4b classify_discovery_confirmation | NO | TC-008 |
| S4b classify_discovery_confirmation | RETURN_TO_ROUTER | TC-012 |
| S4b classify_discovery_confirmation | UNCLEAR | TC-009 |
| S5 classify_app_query_intent | QUERY | TC-001, 006, 008, 010, 014, 015 |
| S5 classify_app_query_intent | RETURN_TO_ROUTER | TC-017 |
| S5 classify_app_query_intent | SWITCH_TASK | TC-004 |
| S5 classify_app_query_intent | UNCLEAR | TC-014 |
| S7 classify_app_selection | VALID_SELECTION | TC-002, 007, 013 |
| S7 classify_app_selection | INVALID_SELECTION | TC-007 |
| S7 classify_app_selection | RETRY_LOOKUP | TC-015 |
| S7 classify_app_selection | RETURN_TO_ROUTER | TC-011 |
| S14 classify_post_discovery_intent | ANOTHER_APP | TC-010 |
| S14 classify_post_discovery_intent | REDISCOVER | TC-005 |
| S14 classify_post_discovery_intent | RETURN_TO_ROUTER | TC-001, 016 |
| S14 classify_post_discovery_intent | UNCLEAR | TC-016 |

7. Technical Constraints
-----------------------

- **Model**: llama-4-scout-17b
- **Integrity**: Silent tool execution; data must be copied exactly from tool output to state schema.
- **Safety**: Do not fetch or output Secret data during resources_list calls.
- **YAML**: All YES/NO intent keys must be quoted (`"YES"` / `"NO"`) to prevent YAML 1.1 boolean coercion.
- **Regex**: Each `extract_data` action must use a single-group regex pattern. The engine always captures `group(1)`.
