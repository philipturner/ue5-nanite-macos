static void ModifyCompilationEnvironment(const FGlobalShaderPermutationParameters& Parameters, FShaderCompilerEnvironment& OutEnvironment)
{
	int32 ResourceType = 1; //RHIGetPreferredClearUAVRectPSResourceType(Parameters.Platform);

	FGlobalShader::ModifyCompilationEnvironment(Parameters, OutEnvironment);
	OutEnvironment.SetDefine(TEXT("ENABLE_CLEAR_VALUE"), 1);
	OutEnvironment.SetDefine(TEXT("RESOURCE_TYPE"), ResourceType);
	OutEnvironment.SetDefine(TEXT("VALUE_TYPE"), TEXT("uint4"));
}
