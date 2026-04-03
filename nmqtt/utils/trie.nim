## Provides O(topic_depth) lookup for matching a published topic against all
## subscription filters, instead of O(n) linear scan over all subscriptions.
##
## The trie is keyed on `/`-delimited topic segments. Wildcard nodes (`+` and
## `#`) are stored as children alongside literal segments. On lookup, the trie
## walks all branches that could match, including wildcard branches.

import tables, strutils

type
  TrieNode* = ref object
    children: Table[string, TrieNode]
    ## Subscription filters that terminate at this node, stored as the
    ## full original filter string. A seq because multiple clients may
    ## subscribe with different filters that resolve to the same trie path
    filters: seq[string]

  TopicTrie* = ref object
    root*: TrieNode


proc newTopicTrie*(): TopicTrie =
  TopicTrie(root: TrieNode())


proc subscribe*(trie: TopicTrie, filter: string) =
  ## Insert a subscription filter into the trie.
  var node = trie.root
  for segment in filter.split('/'):
    if not node.children.hasKey(segment):
      node.children[segment] = TrieNode()
    node = node.children[segment]
  if filter notin node.filters:
    node.filters.add(filter)


proc unsubscribe*(trie: TopicTrie, filter: string) =
  ## Remove a subscription filter from the trie.
  ## Does not prune empty nodes
  var node = trie.root
  for segment in filter.split('/'):
    if not node.children.hasKey(segment):
      return  # Filter wasn't in trie
    node = node.children[segment]
  let idx = node.filters.find(filter)
  if idx >= 0:
    node.filters.del(idx)


proc matchingFilters*(trie: TopicTrie, topic: string): seq[string] =
  ## Return all subscription filters that match the given concrete topic.
  ## Handles `+` (single-level) and `#` (multi-level) wildcards.
  ##
  ## This is the hot path, called once per published message.
  let segments = topic.split('/')

  # Stack-based DFS. Each entry is (node, segment_index).
  var stack: seq[(TrieNode, int)]
  stack.add((trie.root, 0))

  while stack.len > 0:
    let (node, depth) = stack.pop()

    # `#` wildcard: matches everything from this level onward, including
    # zero or more additional levels. If a `#` child exists at any depth,
    # all its filters match.
    if node.children.hasKey("#"):
      let hashNode = node.children["#"]
      for f in hashNode.filters:
        result.add(f)

    # If we've consumed all segments, check for filters at this node
    if depth == segments.len:
      for f in node.filters:
        result.add(f)
      continue

    let segment = segments[depth]

    # Exact match on this segment
    if node.children.hasKey(segment):
      stack.add((node.children[segment], depth + 1))

    # `+` wildcard: matches exactly one level (any segment)
    if node.children.hasKey("+"):
      stack.add((node.children["+"], depth + 1))
