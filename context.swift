        let finalInput = effectiveInput
        
        return try await container.perform { context in
            // Process input
            let lmInput = try await context.processor.prepare(input: finalInput)
            let promptTokenCount = tokenLength(lmInput.text.tokens)
            
            // Check effective context limit
            guard promptTokenCount <= effectiveContextLimit else {
                throw ContextLimitError.exceededAfterTrimming(
                    limit: effectiveContextLimit,
                    promptTokens: promptTokenCount
                )
            }
            
            // Create cache
            var cache: [any KVCache] = context.model.newCache(parameters: parameters)
            
            let remaining = try context.model.prepare(lmInput, cache: cache, windowSize: parameters.prefillStepSize)
                            
            // Submit input for generation
            let generationStream = try generate (
                input: lmInput,
                cache: cache,
                parameters: parameters,
                context: context,
                cacheCoordinator: container.cacheCoordinator
            )
            
            // Gather the generated tokens
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
            if let stats = container.cacheCoordinator?.pagedCache?.stats {
                NSLog("Prefill cache hits: \(stats.cacheHits), misses: \(stats.cacheMisses), allocations: \(stats.allocatedBlocks) / \(stats.totalBlocks) blocks, free: \(stats.freeBlocks) blocks, evicted: \(stats.evictions)")
                if container.cacheCoordinator!.isHybrid {
                    let ssmStats = container.cacheCoordinator!.ssmStateCache
                    NSLog("SSM hits: \(ssmStats.hits) / misses: \(ssmStats.misses)")
                }
            }
            
            // Structure the output
            let rawOutput = rawOutputStorage.consume()
            let resolvedOutput = output.isEmpty ? rawOutput : output
            let resolvedAnalysis = reasoning.isEmpty ? nil : reasoning
            
            return ChatRunResult(
                output: resolvedOutput,
                analysis: resolvedAnalysis,
                promptTokens: promptTokenCount,
                completionInfo: capturedCompletionInfo,
                toolCalls: toolCalls,
                rawText: rawOutput
            )
        }