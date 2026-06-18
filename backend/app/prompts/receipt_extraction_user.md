Read this receipt image carefully and return exactly this JSON object shape:

{
  "merchant": "",
  "date": "",
  "amount": 0,
  "currency": "INR",
  "category": "Personal",
  "notes": "",
  "lineItems": [],
  "confidence": 0,
  "warnings": []
}

Rules:
- Return only the JSON object. No greeting, no summary, no markdown, no code fence.
- Use ISO 8601 for "date" when visible.
- "amount" is the final total paid on the receipt.
- "currency" must be a three-letter ISO code when visible.
- "category" should be a short expense category suitable for autofill.
- Put uncertainty in "warnings" instead of prose outside the JSON.
- "lineItems" must be an array. Each item should be an object with these keys when visible:
  - "originalText"
  - "detectedLanguage"
  - "itemName"
  - "normalizedName"
  - "brand"
  - "quantity"
  - "unit"
  - "unitPrice"
  - "lineTotal"
  - "discount"
  - "category"
  - "confidence"
- "normalizedName" should be stable English for comparison across stores and languages:
  - melk, milk, doodh -> milk
  - brod, bread -> bread
  - kylling, chicken -> chicken
