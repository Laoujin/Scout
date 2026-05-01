# Comparison

Where Scout sits relative to other open-source deep-research projects and the SaaS pages-style products.

## Open-source

| Stars | Repo                                                | How it works                                                                              |
|------:|-----------------------------------------------------|-------------------------------------------------------------------------------------------|
|   520 | [199-biotechnologies/claude-deep-research-skill][1] | Fire-and-forget — `deep research: <topic>` in a fresh `claude` session                    |
|   503 | [weizhena/Deep-Research-skills][2]                  | Slash commands — `/research` → `/research-deep` → `/research-report`, human gates between |
| 26.6k | [assafelovic/gpt-researcher][3]                     | Python CLI / Docker, OpenAI-default (Claude swap needs API key)                           |
| 11.2k | [langchain-ai/open_deep_research][4]                | LangGraph runner                                                                          |
| 28.1k | [stanford-oval/storm][5]                            | Wikipedia-style article generator                                                         |

[1]: https://github.com/199-biotechnologies/claude-deep-research-skill
[2]: https://github.com/weizhena/Deep-Research-skills
[3]: https://github.com/assafelovic/gpt-researcher
[4]: https://github.com/langchain-ai/open_deep_research
[5]: https://github.com/stanford-oval/storm

## SaaS

| Product                     | How it works                                                       |
|-----------------------------|--------------------------------------------------------------------|
| Perplexity + Pages          | Mobile Deep Research → "Create Page" → `perplexity.ai/page/<slug>` |
| ChatGPT Deep Research       | Mobile Deep Research → Share link (read-only thread)               |
| Google Gemini Deep Research | Mobile Deep Research → Export to Google Doc                        |

## Full benchmark

For a head-to-head run on the same topic, see [`comparison/COMPARISON.md`](https://github.com/Laoujin/Scout-Atlas/blob/main/comparison/COMPARISON.md) in the Scout-Atlas repo.
