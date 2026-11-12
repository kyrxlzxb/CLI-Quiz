# Additional Requirements: Curved Branch Extraction for Road-Sign SVGs

## 1. Purpose

Extend the existing road-sign image-to-SVG pipeline to support independent highlighting of curved branches, return bends, shaft-width changes, and routes through grade-separated intersections with bypass connectors.

For each eligible direction, generate an independent `arrow` SVG representing the complete route from its starting point, including any shared starting shaft, to its destination. The navigation system must be able to recolor this SVG and overlay it on the complete `back` SVG to highlight that route, including with semi-transparent coloring.

These requirements extend the current implementation. Existing straight-branch extraction, arrowhead-template replacement, and special-case exclusions must continue to apply.

## 2. Terminology

| Term | Definition |
|---|---|
| **`back` SVG** | The complete background SVG containing the full road/arrow diagram. |
| **`arrow` SVG** | An independently renderable SVG containing the visible geometry belonging to one eligible route. It may contain multiple disconnected shapes. |
| **Shaft** | The body of an arrow or depicted road, excluding its arrowhead. |
| **Main trunk** | The shared shaft followed before routes diverge. |
| **Branch** | A distinct outgoing route, whether or not it ends in an arrowhead. |
| **Bypass** | A small curved connector allowing movement between roads that do not directly connect at their apparent crossing. |
| **Cut boundary** | A constructed boundary used to separate the selected route from unrelated portions of the full diagram. |

## 3. Existing Behavior to Preserve

The current implementation supports extraction of straight-shaft branches using shaft-line extensions, intersection calculations, and model-assisted identification of relevant junction or turning points.

Preserve this behavior where applicable.

Also preserve the existing eligibility rules:

- Generate an independent `arrow` SVG for each eligible outgoing direction, even if that branch has no arrowhead.
- Continue applying existing special-case exclusions. For example, a branch marked by a no-entry icon must not produce an `arrow` SVG.
- Apply these same rules to newly supported curved branches.

## 4. Complete Background Generation

### 4.1 Trace the entire diagram

Generate the road/arrow geometry in the `back` SVG by tracing the complete visible shape of the source diagram, including all trunks, branches, connectors, and other visible connecting regions.

**Do not construct the background solely by combining the extracted `arrow` SVGs.**

Some complex diagrams contain visible regions that communicate connectivity but are not traversed by any individually highlighted route. Combining the route SVGs may leave these regions uncovered. They must still be preserved in the background.

### 4.2 Standardize detected arrowheads

When a triangular arrowhead is detected, apply the existing template-based replacement method to produce the established standardized arrowhead shape.

Full-shape tracing and arrowhead replacement must work together: preserve the complete diagram while standardizing detected arrowheads. Do not add arrowheads to branches that do not have them.

## 5. General Requirements for Independent Route SVGs

Each eligible `arrow` SVG must:

- Begin at the route's actual starting point, including the shared starting portion of the main trunk where applicable.
- Follow the depicted traversable route to its destination.
- Include the appropriate branch shaft and its arrowhead, if present.
- Exclude unrelated branches, unused shaft extensions, and other regions not traversed by the selected route.
- Align with the corresponding geometry in the `back` SVG when overlaid.
- Support independent recoloring and semi-transparent highlighting.

A route is not limited to the portion after a fork. It must include the full applicable path from the common start.

Logical route continuity does not require a single connected SVG shape. Where the source diagram uses gaps to depict an underpass, one `arrow` SVG may contain multiple disconnected visible components.

## 6. Branch Classification

### 6.1 Reference direction

Use the main trunk's forward direction immediately before the branch as the reference direction.

### 6.2 Branch direction

Use the branch's **final intended direction**, rather than its local tangent immediately after leaving the trunk, to determine its angle relative to the reference direction.

Apply the same classification to left and right branches:

| Branch angle | Classification |
|---|---|
| 0° through 90°, inclusive | Forward or lateral branch |
| Greater than 90° | Return-bending branch |

Exactly 90° belongs to the first category.

## 7. Branch Extraction Geometry

### 7.1 Straight-shaft branches at angles of 90° or less

For branches with a straight outgoing shaft and an angle of 90° or less, retain the existing straight-line extension, intersection, and joining method.

### 7.2 Curved branches at angles of 90° or less

Where the incoming trunk is approximately straight and the outgoing branch is curved:

1. Identify the branch boundary on the side that does not directly join the original trunk.
2. Identify the point where that boundary separates from the trunk.
3. Construct a tangent to the curve at that separation point.
4. Extend the tangent toward the trunk until it intersects the opposite boundary that needs to be cut.
5. Use the resulting line and intersection to establish the extraction boundary.
6. Combine the retained shared trunk portion with the selected curved branch to form the complete route.

**Initial implementation decision:** use the separation point as the tangent anchor.

This is a provisional geometric choice. If visual results are unsatisfactory, a later refinement may move the tangent anchor slightly farther along the outgoing curve. Do not automatically introduce that alternative in the initial implementation.

### 7.3 Return-bending branches greater than 90°

For a branch whose final direction turns back by more than 90°, do not use the outgoing curve's tangent extension to construct the junction cut.

Extending that tangent can produce an unwanted pointed projection at the junction.

Instead:

1. Identify the connection point on the boundary where the cut must begin.
2. Through that point, construct a straight line perpendicular to the main trunk's direction immediately before the branch.
3. Extend the line to the opposite shaft boundary.
4. Use this perpendicular cut to separate the selected return-bending route.
5. Retain the starting trunk portion and the complete selected curved branch.

Examples:

- **Upward trunk, branch bending right and back downward:** use a horizontal cut at the relevant connection point.
- **Rightward trunk, branch bending upward and back toward the left:** use a vertical cut.

Apply the same rule symmetrically to left and right return bends.

## 8. Shaft-Width Changes Along the Same Direction

Support routes whose shaft width changes while the route continues in the same direction.

The extracted highlight must follow the depicted width transition.

For example, when an upward shaft becomes narrower:

1. Preserve the wider lower portion up to the point where that width ends.
2. At that point, move inward to the narrower boundary along a horizontal segment.
3. Continue upward along the narrower shaft.

The transition forms a step perpendicular to the direction of travel. Do not replace this step with an arbitrary diagonal taper or extend the wider shaft beyond its depicted end.

Apply the same principle in other orientations: the transition boundary is perpendicular to the local direction of travel.

## 9. Grade-Separated Intersections

### 9.1 Interpret topology separately from visual proximity

Support diagrams in which horizontal and vertical roads cross at different levels.

For example:

- A vertical road is drawn continuously.
- A horizontal road is visually interrupted by the vertical road.
- The horizontal road remains logically traversable from its left segment to its right segment beneath the vertical road.
- The vertical and horizontal roads are not directly connected at the crossing.

Therefore:

- Do not infer a turn from the vertical road onto the horizontal road simply because their visible shapes are adjacent.
- Recognize that two separated portions of the horizontal road can belong to the same traversable road across the depicted underpass.
- Use the depicted bypass connectors to move between the two roads.

### 9.2 Preserve visible crossing gaps

**Do not fill gaps that depict grade separation.**

If a selected route follows the horizontal road beneath the vertical road, its `arrow` SVG must preserve the same visible interruption as the source diagram.

Both visible portions must belong to the same route SVG, even though they are geometrically disconnected.

The highlight must not paint across the gap or visually convert the grade-separated crossing into an at-grade junction.

## 10. Bypass Route Selection

### 10.1 Only one bypass is available

When only one bypass connects the incoming road to the crossing road, use that bypass for routes to either side of the crossing road, subject to the existing eligibility and restriction rules.

Example: if only a left-side bypass exists:

- A route to the left enters the horizontal road through the left-side bypass and continues left.
- A route to the right also uses the left-side bypass, then follows the horizontal road toward the right, passing beneath the crossing while preserving its visible gap.

Do not create a direct connection at the crossing.

### 10.2 Bypasses are available on both sides

When bypasses exist on both sides, select the bypass on the destination's side.

This rule applies regardless of whether that bypass is nearer to or farther from the route's starting point.

For example, if the right-side bypass is located beyond the horizontal crossing:

1. Continue along the vertical trunk past the crossing.
2. Reach the right-side bypass.
3. Follow its return bend onto the right-hand horizontal road.
4. Continue toward the right-hand destination.

Do not use the nearer left-side bypass merely because it is encountered first.

## 11. Bypass Entry and Exit Cuts

A bypass route must include only the portions actually traversed:

1. The incoming trunk from the route's start to the bypass entrance.
2. The bypass connector itself.
3. The destination road from the bypass exit toward the selected destination.

Exclude unused road extensions beyond those junctions.

### 11.1 General cutting rule

At a bypass entrance or exit, construct the necessary cut through the relevant connection point, perpendicular to the local direction of the road shaft being cut.

Thus:

- Cutting a vertical shaft uses a horizontal line.
- Cutting a horizontal shaft uses a vertical line.
- For other orientations, use the equivalent perpendicular direction.

### 11.2 Example: upward trunk to leftward horizontal road

Consider a bypass that leaves an upward vertical trunk, curves toward the upper left, and joins a leftward horizontal road.

The horizontal road may extend a short distance to the right of the bypass junction. That short segment is not part of the selected leftward route.

Construct the route as follows:

1. At the bypass entrance, identify the relevant connection point on the upper side of the departing bypass shaft.
2. Draw a horizontal cut through the vertical trunk.
3. Retain the starting vertical trunk portion up to the bypass entrance.
4. Include the bypass.
5. At its connection to the horizontal road, draw a vertical cut through the horizontal shaft.
6. Retain the horizontal shaft extending toward the left-hand destination and its arrowhead, if present.
7. Exclude the unused horizontal segment to the right of the bypass junction.

The resulting `arrow` SVG is the complete selected route formed by these retained portions.

## 12. Acceptance Criteria

The implementation must satisfy the following cases:

| Case | Expected result |
|---|---|
| Existing straight branch | Existing extraction behavior continues to work. |
| Eligible branch without an arrowhead | An independent route SVG is generated. |
| Branch excluded by an existing no-entry rule | No route SVG is generated for that branch. |
| Background contains regions unused by all extracted routes | Those regions remain present in the fully traced `back` SVG. |
| Detected triangular arrowhead | Existing template-based standardization is applied. |
| Curved branch with a final direction ≤90° from the incoming trunk | Uses tangent-based extraction, initially anchored at the separation point. |
| Branch at exactly 90° | Uses the ≤90° category. |
| Return-bending branch >90° | Uses a cut perpendicular to the incoming trunk and avoids the pointed projection caused by tangent extension. |
| Same-direction shaft narrowing | Preserves the width change with a perpendicular step. |
| Grade-separated crossing | Does not permit a direct turn between the crossing roads. |
| Route passing beneath another road | Preserves the visible gap within a single route SVG containing disconnected components. |
| Only one bypass exists | Routes to either side use that bypass. |
| Bypasses exist on both sides | Each route uses the bypass on its destination side, even when that bypass is farther away. |
| Unused shaft stub at a bypass junction | The stub is excluded using the appropriate perpendicular cut. |
| Recolored or semi-transparent route overlaid on `back` | The complete selected route aligns with the background and highlights only the intended visible route geometry. |
