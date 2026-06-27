import urllib.request
import json
import os
from datetime import datetime, timezone
from supabase import create_client
 
URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
 
SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_KEY"]
 
 
def fetch():
    with urllib.request.urlopen(URL) as r:
        return json.load(r)
 
 
def to_row(model_name, entry):
    row = {"model": model_name}
    row["litellm_provider"] = entry.get("litellm_provider") or None
    row["mode"] = entry.get("mode") or None
 
    row["max_input_tokens"] = entry.get("max_input_tokens") or None
    row["max_output_tokens"] = entry.get("max_output_tokens") or None
    row["max_tokens"] = entry.get("max_tokens") or None
 
    inp = entry.get("input_cost_per_token", None)
    out = entry.get("output_cost_per_token", None)
    row["input_cost_per_token"] = inp if inp is not None else None
    row["output_cost_per_token"] = out if out is not None else None
    row["input_cost_per_1m"] = round(inp * 1_000_000, 6) if inp is not None else None
    row["output_cost_per_1m"] = round(out * 1_000_000, 6) if out is not None else None
 
    row["cache_creation_input_token_cost"] = entry.get("cache_creation_input_token_cost") or None
    row["cache_read_input_token_cost"] = entry.get("cache_read_input_token_cost") or None
    row["output_cost_per_reasoning_token"] = entry.get("output_cost_per_reasoning_token") or None
 
    bool_fields = [
        "supports_vision",
        "supports_function_calling",
        "supports_parallel_function_calling",
        "supports_tool_choice",
        "supports_reasoning",
        "supports_prompt_caching",
        "supports_response_schema",
        "supports_system_messages",
        "supports_audio_input",
        "supports_audio_output",
        "supports_web_search",
    ]
    for f in bool_fields:
        val = entry.get(f, None)
        row[f] = bool(val) if val is not None else None
 
    now = datetime.now(timezone.utc)
    row["fetched_at"] = now.isoformat()
    row["snapshot_date"] = now.date().isoformat()
    return row
 
 
def main():
    print("Fetching LiteLLM model data...")
    data = fetch()
 
    models = {k: v for k, v in data.items() if k != "sample_spec"}
    print(f"Found {len(models)} models")
 
    rows = [to_row(name, entry) for name, entry in models.items()]
 
    today = rows[0]["snapshot_date"]
    supabase = create_client(SUPABASE_URL, SUPABASE_KEY)
 
    # Remove any existing snapshot from today, so re-runs don't create duplicates
    # but older snapshots (history) are left untouched
    supabase.table("raw_litellm_pricing").delete().eq("snapshot_date", today).execute()
    print(f"Cleared any existing rows for {today}")
 
    batch_size = 500
    for i in range(0, len(rows), batch_size):
        batch = rows[i:i + batch_size]
        supabase.table("raw_litellm_pricing").insert(batch).execute()
        print(f"Inserted rows {i + 1} to {i + len(batch)}")
 
    print("Done!")
 
 
if __name__ == "__main__":
    main()
