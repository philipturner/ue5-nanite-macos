// Copyright Epic Games, Inc. All Rights Reserved.

inline bool NaniteAtomicsSupported()
{
#if PLATFORM_APPLE
	// Force-enable Nanite on Apple platforms, using 32-bit atomics under the hood
	bool bAtomicsSupported = true;
#else

	// Are 64bit image atomics supported by the GPU/Driver/OS/API?
	bool bAtomicsSupported = GRHISupportsAtomicUInt64;

#if PLATFORM_WINDOWS
	const ERHIInterfaceType RHIInterface = RHIGetInterfaceType();
	const bool bIsDx11 = RHIInterface == ERHIInterfaceType::D3D11;
	const bool bIsDx12 = RHIInterface == ERHIInterfaceType::D3D12;

	static const auto NaniteRequireDX12CVar = IConsoleManager::Get().FindConsoleVariable(TEXT("r.Nanite.RequireDX12"));
	static const uint32 NaniteRequireDX12 = (NaniteRequireDX12CVar != nullptr) ? NaniteRequireDX12CVar->GetInt() : 1;

	if (bAtomicsSupported && NaniteRequireDX12 != 0)
	{
		// Only allow Vulkan or D3D12
		bAtomicsSupported = !bIsDx11;

		// Disable DX12 vendor extensions unless DX12 SM6.6 is supported
		if (NaniteRequireDX12 == 1 && bIsDx12 && !GRHISupportsDX12AtomicUInt64)
		{
			// Vendor extensions currently support atomic64, but SM 6.6 and the DX12 Agility SDK are reporting that atomics are not supported.
			// Likely due to a pre-1909 Windows 10 version, or outdated drivers without SM 6.6 support.
			// See: https://devblogs.microsoft.com/directx/gettingstarted-dx12agility/
			bAtomicsSupported = false;
		}
	}
#endif
#endif

	return bAtomicsSupported;
}
