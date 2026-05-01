# What is this?

This is a custom fork of [Swama](https://github.com/Trans-N-ai/swama) by @Trans-N-ai
The original doc: [README_ORIGINAL.md](https://github.com/viktike/swama/blob/new/README_ORIGINAL.md) 

## What's new?

There are several small improvements in this project:
 - Removed the hardcoded multimodal context limit
 - Various tool call improvements, for example: added tool call index: [merged](https://github.com/Trans-N-ai/swama/pull/111)

### LLM/VLM inference library

 - [mlx-swift-lm](https://github.com/ml-explore/mlx-swift-lm/) integration is updated to version 3 from version 2
 - Changed over from mlx-swift-lm to [vmlx-swift-lm](https://github.com/viktike/vmlx-swift-lm) by @osaurus-ai. This adds TurboQuant and Prompt Caching capabilities, Gemma4 support, MXFP model weight quantization improvements, etc...
 - Added model support for the following model_type:
   - qwen3_vl_moe (Alibaba's Qwen3 VL 30B A3B, based on qwen3_vl and qwen3_moe)
   - glm4v (Z.ai's GLM 4.6V Flash, based on GLM-OCR)

### Whisper improvements
 - Added utterance (segments) output format with timestamps (verbose_json output format)
 - Added 8bit and floating point 16bit whisper model compatibility [merged](https://github.com/Trans-N-ai/swama/pull/112)

# How to use

## KV cache quantization:

KVCacheQuantization reduces memory requirements during inference with slight reduction of quality: 

 - Set your client's OpenAI key to a single integer for the level of quantization: Authorization: Bearer 8
 - For TurboQuant, set these custom headers in you client:
   - X-Turbo-Quant-Key-bits: 4
   - X-Turbo-Quant-Value-bits: 3

## Prompt caching

Prompt cache reduces prefill time in a multi-turn chat scenario by storing computed prompt prefixes from previous turns.

To enable, navigate to your model's directory (.swama/models/mlx-community/my-model), edit the **config.json**, add these new keys to the top level:
 - "max_cache_blocks": 4096 - Number of blocks (see below) to store  
 - "page_block_size": 64 - Number of prompt tokens stored in a single block
 - "max_ssm_entries": 4 - Number of previous chat turn states to store 

The precomputed caches gets evicted with the model itself.

# Recommendation

Use it headless on a dedicated Mac Mini M4. Enable SSH, disable sleep. Use screen or tmux to run `swama serve`. Don't log in the GUI. Rationale: WindowServer in MacOS consumes around 2 GB being idle.

# Notes

Binary "release" is not notarized / signed.