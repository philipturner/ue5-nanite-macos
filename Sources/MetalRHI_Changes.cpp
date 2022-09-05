// Copyright Epic Games, Inc. All Rights Reserved.

void FMetalDynamicRHI::Init()
{
	GRHIPersistentThreadGroupCount = 1440; // TODO: Revisit based on vendor/adapter/perf query

	// Command lists need the validation RHI context if enabled, so call the global scope version of RHIGetDefaultContext() and RHIGetDefaultAsyncComputeContext().
	GRHICommandList.GetImmediateCommandList().SetContext(::RHIGetDefaultContext());
	GRHICommandList.GetImmediateAsyncComputeCommandList().SetComputeContext(::RHIGetDefaultAsyncComputeContext());

	FRenderResource::InitPreRHIResources();
	GIsRHIInitialized = true;
}
