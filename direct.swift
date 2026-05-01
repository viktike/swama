        // Prepare once for token count
        let lmInput = try await container.prepare(input: effectiveInput)
        let promptTokens = tokenLength(lmInput.text.tokens)

        guard promptTokens <= effectiveContextLimit else {
            throw ContextLimitError.exceededAfterTrimming(
                limit: effectiveContextLimit,
                promptTokens: promptTokens
            )
        }
        
        let generationStream = try await container.generate(
            input: lmInput,
            parameters: parameters
        )

        var output = ""
        var reasoning = ""
        var capturedCompletionInfo: GenerateCompletionInfo? = nil
        var toolCalls: [MLXLMCommon.ToolCall] = []

        for await generationEvent in generationStream {
            switch generationEvent {
            case let .reasoning(reasoningString):
                rawOutputStorage.append(reasoningString)
                onToken?(reasoningString)
                if onToken == nil {
                    reasoning += reasoningString
                }
            case let .chunk(chunkString):
                rawOutputStorage.append(chunkString)
                onToken?(chunkString)
                if onToken == nil {
                    output += chunkString
                }
                
            case let .info(info):
                capturedCompletionInfo = info
                
            case let .toolCall(toolCall):
                toolCalls.append(toolCall)
                onToolCall?(toolCall)
            }
        }

        // Log cache hit stats
        if let coordinator = container.cacheCoordinator {
            if let stats = coordinator.pagedCache?.stats {
                NSLog("Prefill cache hits: \(stats.cacheHits), misses: \(stats.cacheMisses), allocations: \(stats.allocatedBlocks) / \(stats.totalBlocks) blocks, free: \(stats.freeBlocks) blocks, evicted: \(stats.evictions)")
            }
            if coordinator.isHybrid {
                let ssmStats = coordinator.ssmStateCache
                NSLog("SSM hits: \(ssmStats.hits) / misses: \(ssmStats.misses)")
            }
        }
        
        let rawOutput = rawOutputStorage.consume()
        let resolvedOutput = output.isEmpty ? rawOutput : output
        let resolvedAnalysis = reasoning.isEmpty ? nil : reasoning

        return ChatRunResult(
            output: resolvedOutput,
            analysis: resolvedAnalysis,
            promptTokens: promptTokens,
            completionInfo: capturedCompletionInfo,
            toolCalls: toolCalls,
            rawText: rawOutput
        )