# Lessons Learned

This directory contains detailed lessons learned documents from significant implementation efforts in this repository.

## Purpose

Lessons learned documents capture:
- **Process**: How we approached the implementation
- **Problems**: Issues encountered and debugging steps
- **Solutions**: How we solved problems and why
- **Insights**: What we learned that will help future work
- **Time investment**: Effort breakdown for similar future tasks

## Difference from ADRs

| Document Type | ADRs (Architecture Decision Records) | Lessons Learned |
|---------------|-------------------------------------|-----------------|
| **Focus** | What decisions were made and why | How we got there and what went wrong/right |
| **Audience** | Future developers understanding architecture | Team members doing similar work |
| **Content** | Alternatives, trade-offs, consequences | Problems, debugging, insights |
| **Timing** | Written when decision is made | Written after implementation is complete |
| **Format** | Structured (Status, Context, Decision, Consequences) | Narrative with specific examples |

## Documents

- [Tablet Mode Implementation](./tablet-mode-implementation.md) - Touchscreen gestures, auto-rotation, and OSK for Framework 12 laptop

## When to Create a Lessons Learned Document

Create a lessons learned document when:
- Implementation took longer than expected due to debugging
- Multiple approaches were tried before finding the right solution
- Subtle issues were discovered that would benefit others
- The process revealed important patterns or anti-patterns
- Time investment was significant (>2 hours of work)

## Template

When creating a new lessons learned document, include:

1. **Executive Summary**: What was built, key outcomes, time spent
2. **What We Built**: Technical description of the implementation
3. **Critical Lessons Learned**: Numbered lessons with problem/solution/takeaway
4. **What Went Well**: Successes to repeat
5. **What Could Be Improved**: Areas for enhancement
6. **Recommendations**: Future work and improvements
7. **Conclusion**: Summary, key takeaways, time breakdown
8. **References**: Links to related ADRs, docs, external resources

## Contributing

When you complete a significant implementation effort:
1. Create a lessons learned document in this directory
2. Name it descriptively: `feature-name-implementation.md`
3. Link to related ADRs and documentation
4. Update this README with a link to your document
