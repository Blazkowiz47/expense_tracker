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
- Norwegian dates such as 17.06.2026 must be returned as 2026-06-17. Be careful not to confuse 2026 with 2016.
- "amount" is the final total paid on the receipt.
- "currency" must be a three-letter ISO code when visible.
- "category" should be a short expense category suitable for autofill.
- Put uncertainty in "warnings" instead of prose outside the JSON.
- Do not include loyalty/app/customer registration lines as "lineItems". For REMA 1000, ignore lines like "REMA-appen er registrert 17498360".
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
  - "tags"
  - "confidence"
- "tags" must be an array of short lowercase labels for item-level analysis. Examples: ["chocolate", "guilty pleasure"], ["vegetables"], ["staple"], ["household"]. Use [] when unsure.
- "normalizedName" should be stable English for comparison across stores and languages:
  - melk, milk, doodh -> milk
  - brod, bread -> bread
  - kylling, chicken -> chicken
