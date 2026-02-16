Requirement Document: Type-A Migration Agent (TMA)
=================================================

1. Project Overview
------------------

This document defines the functional requirements and state machine configuration for an agentic AI system assisting with application migrations. It utilizes a hierarchical model where a central Routing Agent (Rachel) delegates tasks to a Type-A Migration Agent (TMA).

2. Global Settings & Schema
--------------------------

The following configurations apply to the entire session of the Type-A Migration Agent.

2.1 Settings
~~~~~~~~~~~

```
initial_state: State 1: derive_app_search_q

agent_name: type-a-app-migration

terminal_state: State 15: end

empty_response_retry_count: 3

terminator_env_var: AGENT_MESSAGE_TERMINATOR
```

2.2 State Schema (Data Storage)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

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

discovery_workloads: Dict (Extracted K8s workload names)

discovery_network: Dict (Services/Routes)

discovery_storage: Dict (PVCs)

_should_return_to_routing: Boolean (Flag for session manager)
```

3. Detailed Workflow Logic: State Definitions
-------------------------------------------

State 1: derive_app_search_q
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Temperature: 0.1

```
Prompt: > "You are a migration assistant. Extract the specific application name, ID, or namespace from the user message.

CRITICAL: If the user message is generic (e.g., 'migration', 'ooo', 'help me'), output EXACTLY 'Q: NONE'.
User message: '{last_user_message}'
Output ONLY: Q: <search_substring>"
```

Response Analysis & Propagation:

Condition: "Q: NONE" -> Transition to State 4: waiting_app_query.

Condition: "Q: <substring>" -> Action: extract_data to app_search_q. Transition to State 2.

---

State 2: search_app_catalog_normalize
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Allowed Tools: search_app_catalog

Data Storage: Save full LLM response to app_catalog_candidates.

```
Prompt: > "Execute search_app_catalog(q='{app_search_q}', limit=50).

After the tool returns, output a normalized candidate list (unique tuples only).

If none found, output exactly: CANDIDATES: NONE.

Otherwise output:
CANDIDATES:

app_id=... | app_name=... | namespace=... | source_cluster=... | destination_cluster=..."
```

Transitions: Success -> State 3: format_lookup_status.

---

State 3: format_lookup_status
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Data Storage: Save full response to app_lookup_results.

```
Prompt: > "Convert the normalized candidate list into the required lookup output format.

Candidates: {app_catalog_candidates}.
If 0 matches: STATUS: NONE | MESSAGE: I couldn't find any matching apps in the catalog. Please provide one of: app_id, app name, namespace, source cluster, or destination cluster.
If 1 match: STATUS: UNIQUE | APP_ID: <id> | APP_NAME: <name> | NAMESPACE: <ns> | SOURCE_CLUSTER: <src> | DESTINATION_CLUSTER: <dest>
If multiple matches: STATUS: MULTIPLE | OPTIONS: ... | MESSAGE: Please select an option number (1-15) or provide the app_id to continue."
```

Response Analysis:

Condition: "STATUS: UNIQUE" -> Action: extract_data for all app metadata fields. Transition to State 10.

Condition: "STATUS: MULTIPLE" -> Transition to State 6.

Condition: "STATUS: NONE" -> Transition to State 4.

---

State 4: waiting_app_query
~~~~~~~~~~~~~~~~~~~~~~~~~

Type: waiting

Transitions: user_input -> State 5: classify_app_query_intent.

---

State 5: classify_app_query_intent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: intent_classifier

Intent Prompt:

```
"The user said: '{user_input}'. Analyze their intent:

RETURN_TO_ROUTER: user wants to go back/stop/cancel or mentions a different topic like 'laptop' or 'email'

QUERY: user is providing a search term or application identifier to look up
Respond with only the label."
```

Intent Actions:

RETURN_TO_ROUTER / SWITCH_TASK: Action: Set _should_return_to_routing: true. Transition to State 15.

QUERY: Transition to State 1: derive_app_search_q.

---

State 6: waiting_app_selection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: waiting

Transitions: user_input -> State 7: classify_app_selection.

---

State 7: classify_app_selection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: intent_classifier

Intent Prompt:

```
"The user said: '{user_input}'. The options provided were: {app_lookup_results}.
Determine intent:

RETURN_TO_ROUTER: user wants to cancel or switch topics

RETRY_LOOKUP: user wants to search again with a new query

VALID_SELECTION: user picked an option number (1-15) or a specific app_id from the list

INVALID_SELECTION: selection doesn't match any option
Respond with only the label."
```

Intent Actions:

RETURN_TO_ROUTER / SWITCH_TASK: Transition to State 15.

RETRY_LOOKUP: Transition to State 4.

VALID_SELECTION: Action: data_storage of input to selected_app_choice. Transition to State 8.

INVALID_SELECTION: Transition to State 6.

---

State 8: resolve_app_selection
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Prompt:

```
"Resolve the user choice '{selected_app_choice}' to exactly one option from the list below:
{app_lookup_results}
If resolved uniquely, output: STATUS: UNIQUE | APP_ID: <id> | APP_NAME: <name> | NAMESPACE: <ns> | SOURCE_CLUSTER: <src> | DESTINATION_CLUSTER: <dest>
Otherwise, output: STATUS: ERROR | MESSAGE: Please select one valid option number."
```

Response Analysis:

Condition: "STATUS: UNIQUE" -> Action: extract_data to metadata fields. Transition to State 10.

Condition: "STATUS: ERROR" -> Transition to State 6.

---

State 9: waiting_post_discovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: waiting

Transitions: user_input -> State 14: classify_post_discovery_intent.

---

State 10: discover_workloads
~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Allowed Tools: oc_get_deployments, oc_get_statefulsets, oc_get_daemonsets

Data Storage: discovery_workloads: "llm_response"

Prompt:

```
"You have identified the application in namespace '{namespace}'.
Call the tools to list Deployments, StatefulSets, and DaemonSets in this namespace.
Output ONLY the names of the resources found, grouped by kind. Do not invent values."
```

Transitions: Success -> State 11.

---

State 11: discover_networking
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Allowed Tools: oc_get_services, oc_get_routes, oc_get_ingresses

Data Storage: discovery_network: "llm_response"

Prompt:

```
"In namespace '{namespace}', call the tools to list Services, Routes, and Ingresses.
Output the names and hostnames for these resources. Do not fetch Secret data."
```

Transitions: Success -> State 12.

---

State 12: discover_storage
~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

Allowed Tools: oc_get_pvcs

Data Storage: discovery_storage: "llm_response"

Prompt:

```
"In namespace '{namespace}', call oc_get_pvcs.
List the names of the PVCs found. If none, state 'STORAGE: NONE'."
```

Transitions: Success -> State 13.

---

State 13: summarize_discovery
~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: llm_processor

```
Prompt: > "You have discovered the following for App '{app_name}' (ID: {app_id}):

Workloads: {discovery_workloads}
Network: {discovery_network}
Storage: {discovery_storage}
Summarize this discovery conversationally for the user. Mention the App context and the OpenShift resources found.
End by asking: 'Do you want to look up another app, re-run discovery, or return to the main menu?'"
```

Transitions: Success -> State 9.

---

State 14: classify_post_discovery_intent
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Type: intent_classifier

Intent Prompt:

```
"The user said: '{user_input}'. Analyze intent:

ANOTHER_APP: user wants to search for a new application

REDISCOVER: user wants to re-run the scan for the current namespace

RETURN_TO_ROUTER: user wants to go back to the router agent
Respond with only the label."
```

Intent Actions:

ANOTHER_APP: Transition to State 4.

REDISCOVER: Transition to State 10.

RETURN_TO_ROUTER: Transition to State 15.

---

State 15: end
~~~~~~~~~~~~

Type: terminal

Reset Behavior: - clear_data: All business fields and retry counters (excluding _should_return_to_routing).

4. Technical Constraints
-----------------------

Model: llama-4-scout-17b.

Integrity: Silent tool execution; data must be copied exactly from tool output to state schema.

Safety: Do not fetch or output Secret data during oc_get calls.