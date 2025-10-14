#!/usr/bin/env python3
"""
Patch surya-ocr decoder to handle missing SDPA attention implementation.
Falls back to 'eager' attention when 'sdpa' is not available.
"""
import site
import os

decoder_path = os.path.join(site.getsitepackages()[0], 'surya/model/ordering/decoder.py')

with open(decoder_path, 'r') as f:
    content = f.read()

# Patch self_attn initialization
old_self_attn = "self.self_attn = MBART_ATTENTION_CLASSES[config._attn_implementation]("
new_self_attn = "impl = config._attn_implementation if config._attn_implementation in MBART_ATTENTION_CLASSES else 'eager'; self.self_attn = MBART_ATTENTION_CLASSES[impl]("
content = content.replace(old_self_attn, new_self_attn)

# Patch encoder_attn initialization
old_encoder_attn = "self.encoder_attn = MBART_ATTENTION_CLASSES[config._attn_implementation]("
new_encoder_attn = "impl = config._attn_implementation if config._attn_implementation in MBART_ATTENTION_CLASSES else 'eager'; self.encoder_attn = MBART_ATTENTION_CLASSES[impl]("
content = content.replace(old_encoder_attn, new_encoder_attn)

with open(decoder_path, 'w') as f:
    f.write(content)

print(f"✓ Patched {decoder_path}")
