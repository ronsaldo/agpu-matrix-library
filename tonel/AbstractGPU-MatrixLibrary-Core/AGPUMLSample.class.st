"
Quick example that shows how to use compute shaders for doing Matrix multiplication on the GPU.
"
Class {
	#name : #AGPUMLSample,
	#superclass : #Object,
	#pools : [
		'AGPUConstants'
	],
	#category : #'AbstractGPU-MatrixLibrary-Core'
}

{ #category : #examples }
AGPUMLSample class >> exampleQuickSample [
	| device shaderSource shader shaderSignature computePipeline leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList leftMatrixExtent rightMatrixExtent outputMatrixExtent leftMatrix rightMatrix outputMatrix uploadBuffer readbackBuffer leftMatrixBuffer rightMatrixBuffer outputMatrixBuffer uploadBufferPointer readbackBufferPointer extentsPushConstants |
	device := AGPU mainDevice.
	
	shaderSignature := device createShaderSignatureBuilder
		"Left input"
		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Right input"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Output"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		addBindingConstant; "Left rows"
		addBindingConstant; "Left columns"

		addBindingConstant; "Right rows"
		addBindingConstant; "Right columns"

		addBindingConstant; "Output rows"
		addBindingConstant; "Output columns"

		build.

	shaderSource := '
#version 450	
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) buffer LeftInputMatrixBlock
{
	float[] elements;
} LeftInputMatrix;

layout(set=1, binding=0, std430) buffer RightInputMatrixBlock
{
	float[] elements;
} RightInputMatrix;

layout(set=2, binding=0, std430) buffer OutputMatrixBlock
{
	float[] elements;
} OutputMatrix;

layout(push_constant) uniform MatricesLayoutBlock
{
	uvec2 leftExtent;
	uvec2 rightExtent;
	uvec2 outputExtent;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.leftExtent.y + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.rightExtent.y + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.outputExtent.y + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	if(any(greaterThanEqual(gl_GlobalInvocationID.xy, MatricesLayout.outputExtent)))
		return;
		
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;

	uint K = MatricesLayout.leftExtent.x;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k)*rightAt(k, j);
		
	outputAt(i, j) = result;
}
' withUnixLineEndings.

	shader := device createOfflineShaderCompiler
		setShaderSource: AGPU_SHADER_LANGUAGE_GLSL stage: AGPU_COMPUTE_SHADER
		sourceText: shaderSource sourceTextLength: shaderSource size;
		compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader.
	computePipeline := device createComputePipelineBuilder
		setShaderSignature: shaderSignature;
		attachShader: shader;
		build.
		
	leftMatrixExtent := 64@64.
	rightMatrixExtent := 64@64.
	outputMatrixExtent := 64@64.
		
	leftMatrix := FloatArray new: leftMatrixExtent x * leftMatrixExtent y.
	rightMatrix := FloatArray new: rightMatrixExtent x * rightMatrixExtent y.
	outputMatrix := FloatArray new: outputMatrixExtent x * outputMatrixExtent y.
	
	1 to: leftMatrix size do: [ :i |
		leftMatrix at: i put: i.
	].
	1 to: rightMatrix size do: [ :i |
		rightMatrix at: i put: 1.0.
	].
	
	uploadBuffer := device createBuffer: (AGPUBufferDescription new
		size: (leftMatrix size + rightMatrix size) * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_SOURCE_BUFFER;
		usage_modes: AGPU_COPY_SOURCE_BUFFER;
		mapping_flags: AGPU_MAP_WRITE_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.

	leftMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: leftMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	rightMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: rightMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	outputMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	readbackBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_DESTINATION_BUFFER;
		usage_modes: AGPU_COPY_DESTINATION_BUFFER;
		mapping_flags: AGPU_MAP_READ_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.
		
	leftMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	leftMatrixBinding bindStorageBuffer: 0 storage_buffer: leftMatrixBuffer.
	
	rightMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	rightMatrixBinding bindStorageBuffer: 0 storage_buffer: rightMatrixBuffer.
	
	outputMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	outputMatrixBinding bindStorageBuffer: 0 storage_buffer: outputMatrixBuffer.
	
	commandQueue := device getDefaultCommandQueue.
	commandListAllocator := device createCommandAllocator: AGPU_COMMAND_LIST_TYPE_DIRECT queue: commandQueue.
	commandList := device createCommandList: AGPU_COMMAND_LIST_TYPE_DIRECT allocator: commandListAllocator initial_pipeline_state: nil.
	
	uploadBufferPointer := uploadBuffer mapBuffer: AGPU_WRITE_ONLY.
	readbackBufferPointer := readbackBuffer mapBuffer: AGPU_READ_ONLY.
	
	LibC memCopy: leftMatrix to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { 
		leftMatrixExtent x.
		leftMatrixExtent y.
		rightMatrixExtent x.
		rightMatrixExtent y.
		outputMatrixExtent x.
		outputMatrixExtent y.
	} asWordArray.
	
	commandList
		"Copy from host buffer into the left buffer."
		pushBufferTransitionBarrier: leftMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: 0
			dest_buffer: leftMatrixBuffer dest_offset: 0 copy_size: leftMatrix size * 4;
		popBufferTransitionBarrier;

		"Copy from host buffer into the right buffer."
		pushBufferTransitionBarrier: rightMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: leftMatrix size * 4
			dest_buffer: rightMatrixBuffer dest_offset: 0 copy_size: rightMatrix size * 4;
		popBufferTransitionBarrier;
	
		setShaderSignature: shaderSignature;
		usePipelineState: computePipeline;
		useComputeShaderResourcesInSlot: leftMatrixBinding slot: 0;
		useComputeShaderResourcesInSlot: rightMatrixBinding slot: 1;
		useComputeShaderResourcesInSlot: outputMatrixBinding slot: 2;
		pushConstants: 0 size: extentsPushConstants size * 4 values: extentsPushConstants;
		dispatchCompute: (outputMatrixExtent x + 7) // 8 group_count_y: (outputMatrixExtent y + 7) // 8 group_count_z: 1;
		
		"Copy from device buffer into the host buffer."
		pushBufferTransitionBarrier: outputMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_SOURCE_BUFFER;
		copyBuffer: outputMatrixBuffer source_offset: 0
			dest_buffer: readbackBuffer dest_offset: 0 copy_size: outputMatrix size * 4;
		popBufferTransitionBarrier;
		
		close.
		
	commandQueue
		addCommandList: commandList;
		finishExecution.
	
	LibC memCopy: readbackBufferPointer to: outputMatrix size: outputMatrix size * 4.
	"
	leftMatrix inspect
	rightMatrix inspect
	outputMatrix inspect
	"
	(Dictionary newFromPairs: {
		#leftMatrix. leftMatrix . 
		#rightMatrix. rightMatrix. 
		#outputMatrix. outputMatrix } ) inspect
	
]

{ #category : #examples2 }
AGPUMLSample class >> exampleSample_1x2_2x1 [
	| device shaderSource shader shaderSignature computePipeline leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList leftMatrixExtent rightMatrixExtent outputMatrixExtent leftMatrix rightMatrix outputMatrix uploadBuffer readbackBuffer leftMatrixBuffer rightMatrixBuffer outputMatrixBuffer uploadBufferPointer readbackBufferPointer extentsPushConstants |
	device := AGPU mainDevice.
	
	shaderSignature := device createShaderSignatureBuilder
		"Left input"
		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Right input"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Output"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		addBindingConstant; "Left rows"
		addBindingConstant; "Left columns"

		addBindingConstant; "Right rows"
		addBindingConstant; "Right columns"

		addBindingConstant; "Output rows"
		addBindingConstant; "Output columns"

		build.

	shaderSource := '
#version 450	
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) buffer LeftInputMatrixBlock
{
	float[] elements;
} LeftInputMatrix;

layout(set=1, binding=0, std430) buffer RightInputMatrixBlock
{
	float[] elements;
} RightInputMatrix;

layout(set=2, binding=0, std430) buffer OutputMatrixBlock
{
	float[] elements;
} OutputMatrix;

layout(push_constant) uniform MatricesLayoutBlock
{
	uvec2 leftExtent;
	uvec2 rightExtent;
	uvec2 outputExtent;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.leftExtent.y + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.rightExtent.y + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.outputExtent.y + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	if(any(greaterThanEqual(gl_GlobalInvocationID.xy, MatricesLayout.outputExtent)))
		return;
		
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;

	uint K = MatricesLayout.leftExtent.x;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k)*rightAt(k, j);
		
	outputAt(i, j) = result;
}
' withUnixLineEndings.

	shader := device createOfflineShaderCompiler
		setShaderSource: AGPU_SHADER_LANGUAGE_GLSL stage: AGPU_COMPUTE_SHADER
		sourceText: shaderSource sourceTextLength: shaderSource size;
		compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader.
	computePipeline := device createComputePipelineBuilder
		setShaderSignature: shaderSignature;
		attachShader: shader;
		build.
		
	leftMatrixExtent := 1@2.
	rightMatrixExtent := 2@1.
	outputMatrixExtent := 1@1.
		
	leftMatrix := { 1.0.  2.0 } asFloatArray.
	rightMatrix := { 10.0.  20.0 } asFloatArray.

	outputMatrix := FloatArray new: outputMatrixExtent x * outputMatrixExtent y.
	
	uploadBuffer := device createBuffer: (AGPUBufferDescription new
		size: (leftMatrix size + rightMatrix size) * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_SOURCE_BUFFER;
		usage_modes: AGPU_COPY_SOURCE_BUFFER;
		mapping_flags: AGPU_MAP_WRITE_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.

	leftMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: leftMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	rightMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: rightMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	outputMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	readbackBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_DESTINATION_BUFFER;
		usage_modes: AGPU_COPY_DESTINATION_BUFFER;
		mapping_flags: AGPU_MAP_READ_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.
		
	leftMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	leftMatrixBinding bindStorageBuffer: 0 storage_buffer: leftMatrixBuffer.
	
	rightMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	rightMatrixBinding bindStorageBuffer: 0 storage_buffer: rightMatrixBuffer.
	
	outputMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	outputMatrixBinding bindStorageBuffer: 0 storage_buffer: outputMatrixBuffer.
	
	commandQueue := device getDefaultCommandQueue.
	commandListAllocator := device createCommandAllocator: AGPU_COMMAND_LIST_TYPE_DIRECT queue: commandQueue.
	commandList := device createCommandList: AGPU_COMMAND_LIST_TYPE_DIRECT allocator: commandListAllocator initial_pipeline_state: nil.
	
	uploadBufferPointer := uploadBuffer mapBuffer: AGPU_WRITE_ONLY.
	readbackBufferPointer := readbackBuffer mapBuffer: AGPU_READ_ONLY.
	
	LibC memCopy: leftMatrix to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { 
		leftMatrixExtent x.
		leftMatrixExtent y.
		rightMatrixExtent x.
		rightMatrixExtent y.
		outputMatrixExtent x.
		outputMatrixExtent y.
	} asWordArray.
	
	commandList
		"Copy from host buffer into the left buffer."
		pushBufferTransitionBarrier: leftMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: 0
			dest_buffer: leftMatrixBuffer dest_offset: 0 copy_size: leftMatrix size * 4;
		popBufferTransitionBarrier;

		"Copy from host buffer into the right buffer."
		pushBufferTransitionBarrier: rightMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: leftMatrix size * 4
			dest_buffer: rightMatrixBuffer dest_offset: 0 copy_size: rightMatrix size * 4;
		popBufferTransitionBarrier;
	
		setShaderSignature: shaderSignature;
		usePipelineState: computePipeline;
		useComputeShaderResourcesInSlot: leftMatrixBinding slot: 0;
		useComputeShaderResourcesInSlot: rightMatrixBinding slot: 1;
		useComputeShaderResourcesInSlot: outputMatrixBinding slot: 2;
		pushConstants: 0 size: extentsPushConstants size * 4 values: extentsPushConstants;
		dispatchCompute: (outputMatrixExtent x + 7) // 8 group_count_y: (outputMatrixExtent y + 7) // 8 group_count_z: 1;
		
		"Copy from device buffer into the host buffer."
		pushBufferTransitionBarrier: outputMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_SOURCE_BUFFER;
		copyBuffer: outputMatrixBuffer source_offset: 0
			dest_buffer: readbackBuffer dest_offset: 0 copy_size: outputMatrix size * 4;
		popBufferTransitionBarrier;
		
		close.
		
	commandQueue
		addCommandList: commandList;
		finishExecution.
	
	LibC memCopy: readbackBufferPointer to: outputMatrix size: outputMatrix size * 4.
	"leftMatrix inspect"
	"rightMatrix inspect"
	"outputMatrix inspect"
	"https://www.symbolab.com/solver/matrix-multiply-calculator/%5Cbegin%7Bpmatrix%7D1%262%5C%5C%203%264%5Cend%7Bpmatrix%7D%5Cbegin%7Bpmatrix%7D10%2620%5C%5C%2030%2640%5Cend%7Bpmatrix%7D?or=input"
	(Dictionary newFromPairs: {
		#leftMatrix. leftMatrix . 
		#rightMatrix. rightMatrix. 
		#outputMatrix. outputMatrix } ) inspect
	
]

{ #category : #examples2 }
AGPUMLSample class >> exampleSample_1x2_2x1_square [
	| device shaderSource shader shaderSignature computePipeline leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList leftMatrixExtent rightMatrixExtent outputMatrixExtent leftMatrix rightMatrix outputMatrix uploadBuffer readbackBuffer leftMatrixBuffer rightMatrixBuffer outputMatrixBuffer uploadBufferPointer readbackBufferPointer extentsPushConstants |
	device := AGPU mainDevice.
	
	shaderSignature := device createShaderSignatureBuilder
		"Left input"
		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Right input"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Output"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		addBindingConstant; "Left rows"
		addBindingConstant; "Left columns"

		addBindingConstant; "Right rows"
		addBindingConstant; "Right columns"

		addBindingConstant; "Output rows"
		addBindingConstant; "Output columns"

		build.

	shaderSource := '
#version 450	
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) buffer LeftInputMatrixBlock
{
	float[] elements;
} LeftInputMatrix;

layout(set=1, binding=0, std430) buffer RightInputMatrixBlock
{
	float[] elements;
} RightInputMatrix;

layout(set=2, binding=0, std430) buffer OutputMatrixBlock
{
	float[] elements;
} OutputMatrix;

layout(push_constant) uniform MatricesLayoutBlock
{
	uvec2 leftExtent;
	uvec2 rightExtent;
	uvec2 outputExtent;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.leftExtent.y + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.rightExtent.y + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.outputExtent.y + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	if(any(greaterThanEqual(gl_GlobalInvocationID.xy, MatricesLayout.outputExtent)))
		return;
		
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;

	uint K = MatricesLayout.leftExtent.x;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k)*rightAt(k, j);
		
	outputAt(i, j) = result;
}
' withUnixLineEndings.

	shader := device createOfflineShaderCompiler
		setShaderSource: AGPU_SHADER_LANGUAGE_GLSL stage: AGPU_COMPUTE_SHADER
		sourceText: shaderSource sourceTextLength: shaderSource size;
		compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader.
	computePipeline := device createComputePipelineBuilder
		setShaderSignature: shaderSignature;
		attachShader: shader;
		build.
		
	leftMatrixExtent := 2@2.
	rightMatrixExtent := 2@2.
	outputMatrixExtent := 2@2.
		
	leftMatrix := { 1.0.  2.0.  0.0.  0.0 } asFloatArray.
	rightMatrix := { 10.0.  0.0.  20.0.  0.0 } asFloatArray.

	outputMatrix := FloatArray new: outputMatrixExtent x * outputMatrixExtent y.
	
	uploadBuffer := device createBuffer: (AGPUBufferDescription new
		size: (leftMatrix size + rightMatrix size) * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_SOURCE_BUFFER;
		usage_modes: AGPU_COPY_SOURCE_BUFFER;
		mapping_flags: AGPU_MAP_WRITE_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.

	leftMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: leftMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	rightMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: rightMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	outputMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	readbackBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_DESTINATION_BUFFER;
		usage_modes: AGPU_COPY_DESTINATION_BUFFER;
		mapping_flags: AGPU_MAP_READ_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.
		
	leftMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	leftMatrixBinding bindStorageBuffer: 0 storage_buffer: leftMatrixBuffer.
	
	rightMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	rightMatrixBinding bindStorageBuffer: 0 storage_buffer: rightMatrixBuffer.
	
	outputMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	outputMatrixBinding bindStorageBuffer: 0 storage_buffer: outputMatrixBuffer.
	
	commandQueue := device getDefaultCommandQueue.
	commandListAllocator := device createCommandAllocator: AGPU_COMMAND_LIST_TYPE_DIRECT queue: commandQueue.
	commandList := device createCommandList: AGPU_COMMAND_LIST_TYPE_DIRECT allocator: commandListAllocator initial_pipeline_state: nil.
	
	uploadBufferPointer := uploadBuffer mapBuffer: AGPU_WRITE_ONLY.
	readbackBufferPointer := readbackBuffer mapBuffer: AGPU_READ_ONLY.
	
	LibC memCopy: leftMatrix to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { 
		leftMatrixExtent x.
		leftMatrixExtent y.
		rightMatrixExtent x.
		rightMatrixExtent y.
		outputMatrixExtent x.
		outputMatrixExtent y.
	} asWordArray.
	
	commandList
		"Copy from host buffer into the left buffer."
		pushBufferTransitionBarrier: leftMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: 0
			dest_buffer: leftMatrixBuffer dest_offset: 0 copy_size: leftMatrix size * 4;
		popBufferTransitionBarrier;

		"Copy from host buffer into the right buffer."
		pushBufferTransitionBarrier: rightMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: leftMatrix size * 4
			dest_buffer: rightMatrixBuffer dest_offset: 0 copy_size: rightMatrix size * 4;
		popBufferTransitionBarrier;
	
		setShaderSignature: shaderSignature;
		usePipelineState: computePipeline;
		useComputeShaderResourcesInSlot: leftMatrixBinding slot: 0;
		useComputeShaderResourcesInSlot: rightMatrixBinding slot: 1;
		useComputeShaderResourcesInSlot: outputMatrixBinding slot: 2;
		pushConstants: 0 size: extentsPushConstants size * 4 values: extentsPushConstants;
		dispatchCompute: (outputMatrixExtent x + 7) // 8 group_count_y: (outputMatrixExtent y + 7) // 8 group_count_z: 1;
		
		"Copy from device buffer into the host buffer."
		pushBufferTransitionBarrier: outputMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_SOURCE_BUFFER;
		copyBuffer: outputMatrixBuffer source_offset: 0
			dest_buffer: readbackBuffer dest_offset: 0 copy_size: outputMatrix size * 4;
		popBufferTransitionBarrier;
		
		close.
		
	commandQueue
		addCommandList: commandList;
		finishExecution.
	
	LibC memCopy: readbackBufferPointer to: outputMatrix size: outputMatrix size * 4.
	"leftMatrix inspect"
	"rightMatrix inspect"
	"outputMatrix inspect"
	"https://www.symbolab.com/solver/matrix-multiply-calculator/%5Cbegin%7Bpmatrix%7D1%262%5C%5C%203%264%5Cend%7Bpmatrix%7D%5Cbegin%7Bpmatrix%7D10%2620%5C%5C%2030%2640%5Cend%7Bpmatrix%7D?or=input"
	(Dictionary newFromPairs: {
		#leftMatrix. leftMatrix . 
		#rightMatrix. rightMatrix. 
		#outputMatrix. outputMatrix } ) inspect
]

{ #category : #examples2 }
AGPUMLSample class >> exampleSample_2x2 [
	| device shaderSource shader shaderSignature computePipeline leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList leftMatrixExtent rightMatrixExtent outputMatrixExtent leftMatrix rightMatrix outputMatrix uploadBuffer readbackBuffer leftMatrixBuffer rightMatrixBuffer outputMatrixBuffer uploadBufferPointer readbackBufferPointer extentsPushConstants |
	device := AGPU mainDevice.
	
	shaderSignature := device createShaderSignatureBuilder
		"Left input"
		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Right input"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Output"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		addBindingConstant; "Left rows"
		addBindingConstant; "Left columns"

		addBindingConstant; "Right rows"
		addBindingConstant; "Right columns"

		addBindingConstant; "Output rows"
		addBindingConstant; "Output columns"

		build.

	shaderSource := '
#version 450	
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) buffer LeftInputMatrixBlock
{
	float[] elements;
} LeftInputMatrix;

layout(set=1, binding=0, std430) buffer RightInputMatrixBlock
{
	float[] elements;
} RightInputMatrix;

layout(set=2, binding=0, std430) buffer OutputMatrixBlock
{
	float[] elements;
} OutputMatrix;

layout(push_constant) uniform MatricesLayoutBlock
{
	uvec2 leftExtent;
	uvec2 rightExtent;
	uvec2 outputExtent;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.leftExtent.y + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.rightExtent.y + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.outputExtent.y + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	if(any(greaterThanEqual(gl_GlobalInvocationID.xy, MatricesLayout.outputExtent)))
		return;
		
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;

	uint K = MatricesLayout.leftExtent.x;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k)*rightAt(k, j);
		
	outputAt(i, j) = result;
}
' withUnixLineEndings.

	shader := device createOfflineShaderCompiler
		setShaderSource: AGPU_SHADER_LANGUAGE_GLSL stage: AGPU_COMPUTE_SHADER
		sourceText: shaderSource sourceTextLength: shaderSource size;
		compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader.
	computePipeline := device createComputePipelineBuilder
		setShaderSignature: shaderSignature;
		attachShader: shader;
		build.
		
	leftMatrixExtent := 2@2.
	rightMatrixExtent := 2@2.
	outputMatrixExtent := 2@2.
		
	leftMatrix := { 1.0.  2.0.  3.0.  4.0 } asFloatArray.
	rightMatrix := { 10.0.  20.0.  30.0.  40.0 } asFloatArray.
	outputMatrix := FloatArray new: outputMatrixExtent x * outputMatrixExtent y.
	
	uploadBuffer := device createBuffer: (AGPUBufferDescription new
		size: (leftMatrix size + rightMatrix size) * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_SOURCE_BUFFER;
		usage_modes: AGPU_COPY_SOURCE_BUFFER;
		mapping_flags: AGPU_MAP_WRITE_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.

	leftMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: leftMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	rightMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: rightMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	outputMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	readbackBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_DESTINATION_BUFFER;
		usage_modes: AGPU_COPY_DESTINATION_BUFFER;
		mapping_flags: AGPU_MAP_READ_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.
		
	leftMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	leftMatrixBinding bindStorageBuffer: 0 storage_buffer: leftMatrixBuffer.
	
	rightMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	rightMatrixBinding bindStorageBuffer: 0 storage_buffer: rightMatrixBuffer.
	
	outputMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	outputMatrixBinding bindStorageBuffer: 0 storage_buffer: outputMatrixBuffer.
	
	commandQueue := device getDefaultCommandQueue.
	commandListAllocator := device createCommandAllocator: AGPU_COMMAND_LIST_TYPE_DIRECT queue: commandQueue.
	commandList := device createCommandList: AGPU_COMMAND_LIST_TYPE_DIRECT allocator: commandListAllocator initial_pipeline_state: nil.
	
	uploadBufferPointer := uploadBuffer mapBuffer: AGPU_WRITE_ONLY.
	readbackBufferPointer := readbackBuffer mapBuffer: AGPU_READ_ONLY.
	
	LibC memCopy: leftMatrix to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { 
		leftMatrixExtent x.
		leftMatrixExtent y.
		rightMatrixExtent x.
		rightMatrixExtent y.
		outputMatrixExtent x.
		outputMatrixExtent y.
	} asWordArray.
	
	commandList
		"Copy from host buffer into the left buffer."
		pushBufferTransitionBarrier: leftMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: 0
			dest_buffer: leftMatrixBuffer dest_offset: 0 copy_size: leftMatrix size * 4;
		popBufferTransitionBarrier;

		"Copy from host buffer into the right buffer."
		pushBufferTransitionBarrier: rightMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: leftMatrix size * 4
			dest_buffer: rightMatrixBuffer dest_offset: 0 copy_size: rightMatrix size * 4;
		popBufferTransitionBarrier;
	
		setShaderSignature: shaderSignature;
		usePipelineState: computePipeline;
		useComputeShaderResourcesInSlot: leftMatrixBinding slot: 0;
		useComputeShaderResourcesInSlot: rightMatrixBinding slot: 1;
		useComputeShaderResourcesInSlot: outputMatrixBinding slot: 2;
		pushConstants: 0 size: extentsPushConstants size * 4 values: extentsPushConstants;
		dispatchCompute: (outputMatrixExtent x + 7) // 8 group_count_y: (outputMatrixExtent y + 7) // 8 group_count_z: 1;
		
		"Copy from device buffer into the host buffer."
		pushBufferTransitionBarrier: outputMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_SOURCE_BUFFER;
		copyBuffer: outputMatrixBuffer source_offset: 0
			dest_buffer: readbackBuffer dest_offset: 0 copy_size: outputMatrix size * 4;
		popBufferTransitionBarrier;
		
		close.
		
	commandQueue
		addCommandList: commandList;
		finishExecution.
	
	LibC memCopy: readbackBufferPointer to: outputMatrix size: outputMatrix size * 4.
	"leftMatrix inspect"
	"rightMatrix inspect"
	"outputMatrix inspect"
	"https://www.symbolab.com/solver/matrix-multiply-calculator/%5Cbegin%7Bpmatrix%7D1%262%5C%5C%203%264%5Cend%7Bpmatrix%7D%5Cbegin%7Bpmatrix%7D10%2620%5C%5C%2030%2640%5Cend%7Bpmatrix%7D?or=input"
	(Dictionary newFromPairs: {
		#leftMatrix. leftMatrix . 
		#rightMatrix. rightMatrix. 
		#outputMatrix. outputMatrix } ) inspect
	
]

{ #category : #examples2 }
AGPUMLSample class >> exampleSmallSample [
	| device shaderSource shader shaderSignature computePipeline leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList leftMatrixExtent rightMatrixExtent outputMatrixExtent leftMatrix rightMatrix outputMatrix uploadBuffer readbackBuffer leftMatrixBuffer rightMatrixBuffer outputMatrixBuffer uploadBufferPointer readbackBufferPointer extentsPushConstants |
	device := AGPU mainDevice.
	
	shaderSignature := device createShaderSignatureBuilder
		"Left input"
		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Right input"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Output"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		addBindingConstant; "Left rows"
		addBindingConstant; "Left columns"

		addBindingConstant; "Right rows"
		addBindingConstant; "Right columns"

		addBindingConstant; "Output rows"
		addBindingConstant; "Output columns"

		build.

	shaderSource := '
#version 450	
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) buffer LeftInputMatrixBlock
{
	float[] elements;
} LeftInputMatrix;

layout(set=1, binding=0, std430) buffer RightInputMatrixBlock
{
	float[] elements;
} RightInputMatrix;

layout(set=2, binding=0, std430) buffer OutputMatrixBlock
{
	float[] elements;
} OutputMatrix;

layout(push_constant) uniform MatricesLayoutBlock
{
	uvec2 leftExtent;
	uvec2 rightExtent;
	uvec2 outputExtent;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.leftExtent.y + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.rightExtent.y + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.outputExtent.y + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	if(any(greaterThanEqual(gl_GlobalInvocationID.xy, MatricesLayout.outputExtent)))
		return;
		
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;

	uint K = MatricesLayout.leftExtent.x;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k)*rightAt(k, j);
		
	outputAt(i, j) = result;
}
' withUnixLineEndings.

	shader := device createOfflineShaderCompiler
		setShaderSource: AGPU_SHADER_LANGUAGE_GLSL stage: AGPU_COMPUTE_SHADER
		sourceText: shaderSource sourceTextLength: shaderSource size;
		compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader.
	computePipeline := device createComputePipelineBuilder
		setShaderSignature: shaderSignature;
		attachShader: shader;
		build.
		
	leftMatrixExtent := 2@2.
	rightMatrixExtent := 2@2.
	outputMatrixExtent := 2@2.
		
	leftMatrix := FloatArray new: leftMatrixExtent x * leftMatrixExtent y.
	rightMatrix := FloatArray new: rightMatrixExtent x * rightMatrixExtent y.
	outputMatrix := FloatArray new: outputMatrixExtent x * outputMatrixExtent y.
	
	leftMatrix at: 1 put: 1.
	leftMatrix at: 2 put: 2.
	leftMatrix at: 3 put: 3.
	leftMatrix at: 4 put: 4.
	
	rightMatrix at: 1 put: 10.
	rightMatrix at: 2 put: 20.
	rightMatrix at: 3 put: 30.
	rightMatrix at: 4 put: 40.
	
	uploadBuffer := device createBuffer: (AGPUBufferDescription new
		size: (leftMatrix size + rightMatrix size) * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_SOURCE_BUFFER;
		usage_modes: AGPU_COPY_SOURCE_BUFFER;
		mapping_flags: AGPU_MAP_WRITE_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.

	leftMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: leftMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	rightMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: rightMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	outputMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	readbackBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_DESTINATION_BUFFER;
		usage_modes: AGPU_COPY_DESTINATION_BUFFER;
		mapping_flags: AGPU_MAP_READ_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.
		
	leftMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	leftMatrixBinding bindStorageBuffer: 0 storage_buffer: leftMatrixBuffer.
	
	rightMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	rightMatrixBinding bindStorageBuffer: 0 storage_buffer: rightMatrixBuffer.
	
	outputMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	outputMatrixBinding bindStorageBuffer: 0 storage_buffer: outputMatrixBuffer.
	
	commandQueue := device getDefaultCommandQueue.
	commandListAllocator := device createCommandAllocator: AGPU_COMMAND_LIST_TYPE_DIRECT queue: commandQueue.
	commandList := device createCommandList: AGPU_COMMAND_LIST_TYPE_DIRECT allocator: commandListAllocator initial_pipeline_state: nil.
	
	uploadBufferPointer := uploadBuffer mapBuffer: AGPU_WRITE_ONLY.
	readbackBufferPointer := readbackBuffer mapBuffer: AGPU_READ_ONLY.
	
	LibC memCopy: leftMatrix to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { 
		leftMatrixExtent x.
		leftMatrixExtent y.
		rightMatrixExtent x.
		rightMatrixExtent y.
		outputMatrixExtent x.
		outputMatrixExtent y.
	} asWordArray.
	
	commandList
		"Copy from host buffer into the left buffer."
		pushBufferTransitionBarrier: leftMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: 0
			dest_buffer: leftMatrixBuffer dest_offset: 0 copy_size: leftMatrix size * 4;
		popBufferTransitionBarrier;

		"Copy from host buffer into the right buffer."
		pushBufferTransitionBarrier: rightMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: leftMatrix size * 4
			dest_buffer: rightMatrixBuffer dest_offset: 0 copy_size: rightMatrix size * 4;
		popBufferTransitionBarrier;
	
		setShaderSignature: shaderSignature;
		usePipelineState: computePipeline;
		useComputeShaderResourcesInSlot: leftMatrixBinding slot: 0;
		useComputeShaderResourcesInSlot: rightMatrixBinding slot: 1;
		useComputeShaderResourcesInSlot: outputMatrixBinding slot: 2;
		pushConstants: 0 size: extentsPushConstants size * 4 values: extentsPushConstants;
		dispatchCompute: (outputMatrixExtent x + 7) // 8 group_count_y: (outputMatrixExtent y + 7) // 8 group_count_z: 1;
		
		"Copy from device buffer into the host buffer."
		pushBufferTransitionBarrier: outputMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_SOURCE_BUFFER;
		copyBuffer: outputMatrixBuffer source_offset: 0
			dest_buffer: readbackBuffer dest_offset: 0 copy_size: outputMatrix size * 4;
		popBufferTransitionBarrier;
		
		close.
		
	commandQueue
		addCommandList: commandList;
		finishExecution.
	
	LibC memCopy: readbackBufferPointer to: outputMatrix size: outputMatrix size * 4.
	"
	leftMatrix inspect
	rightMatrix inspect
	outputMatrix inspect
	"
	(Dictionary newFromPairs: {
		#leftMatrix. leftMatrix . 
		#rightMatrix. rightMatrix. 
		#outputMatrix. outputMatrix } ) inspect
	
]

{ #category : #examples2 }
AGPUMLSample class >> exampleSmallSampleMxKxN [
	| device shaderSource shader shaderSignature computePipeline leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList leftMatrixExtent rightMatrixExtent outputMatrixExtent leftMatrix rightMatrix outputMatrix uploadBuffer readbackBuffer leftMatrixBuffer rightMatrixBuffer outputMatrixBuffer uploadBufferPointer readbackBufferPointer extentsPushConstants |
	device := AGPU mainDevice.
	
	shaderSignature := device createShaderSignatureBuilder
		"Left input"
		beginBindingBank: 1000;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Right input"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		"Output"
		beginBindingBank: 1;
		addBindingBankElement: AGPU_SHADER_BINDING_TYPE_STORAGE_BUFFER bindingPointCount: 1;
		
		addBindingConstant; "Left rows"
		addBindingConstant; "Left columns"

		addBindingConstant; "Right rows"
		addBindingConstant; "Right columns"

		addBindingConstant; "Output rows"
		addBindingConstant; "Output columns"

		build.

	shaderSource := '
#version 450	
layout(local_size_x = 8, local_size_y = 8) in;

layout(set=0, binding=0, std430) buffer LeftInputMatrixBlock
{
	float[] elements;
} LeftInputMatrix;

layout(set=1, binding=0, std430) buffer RightInputMatrixBlock
{
	float[] elements;
} RightInputMatrix;

layout(set=2, binding=0, std430) buffer OutputMatrixBlock
{
	float[] elements;
} OutputMatrix;

layout(push_constant) uniform MatricesLayoutBlock
{
	uvec2 leftExtent;
	uvec2 rightExtent;
	uvec2 outputExtent;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.leftExtent.y + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.rightExtent.y + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.outputExtent.y + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	if(any(greaterThanEqual(gl_GlobalInvocationID.xy, MatricesLayout.outputExtent)))
		return;
		
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;

	uint K = MatricesLayout.leftExtent.x;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k)*rightAt(k, j);
		
	outputAt(i, j) = result;
}
' withUnixLineEndings.

	shader := device createOfflineShaderCompiler
		setShaderSource: AGPU_SHADER_LANGUAGE_GLSL stage: AGPU_COMPUTE_SHADER
		sourceText: shaderSource sourceTextLength: shaderSource size;
		compileShader: AGPU_SHADER_LANGUAGE_DEVICE_SHADER options: '';
			getResultAsShader.
	computePipeline := device createComputePipelineBuilder
		setShaderSignature: shaderSignature;
		attachShader: shader;
		build.
		
	leftMatrixExtent := 2@2.
	rightMatrixExtent := 2@2.
	outputMatrixExtent := 2@2.
		
	leftMatrix := FloatArray new: leftMatrixExtent x * leftMatrixExtent y.
	rightMatrix := FloatArray new: rightMatrixExtent x * rightMatrixExtent y.
	outputMatrix := FloatArray new: outputMatrixExtent x * outputMatrixExtent y.
	
	leftMatrix at: 1 put: 1.
	leftMatrix at: 2 put: 2.
	leftMatrix at: 3 put: 3.
	leftMatrix at: 4 put: 4.
	
	rightMatrix at: 1 put: 10.
	rightMatrix at: 2 put: 20.
	rightMatrix at: 3 put: 30.
	rightMatrix at: 4 put: 40.
	
	uploadBuffer := device createBuffer: (AGPUBufferDescription new
		size: (leftMatrix size + rightMatrix size) * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_SOURCE_BUFFER;
		usage_modes: AGPU_COPY_SOURCE_BUFFER;
		mapping_flags: AGPU_MAP_WRITE_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.

	leftMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: leftMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	rightMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: rightMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	outputMatrixBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_DEVICE_LOCAL;
		main_usage_mode: AGPU_STORAGE_BUFFER;
		usage_modes: ((AGPU_COPY_SOURCE_BUFFER bitOr: AGPU_COPY_DESTINATION_BUFFER) bitOr: AGPU_STORAGE_BUFFER);
		yourself) initial_data: nil.

	readbackBuffer := device createBuffer: (AGPUBufferDescription new
		size: outputMatrix size * 4;
		heap_type: AGPU_MEMORY_HEAP_TYPE_HOST;
		main_usage_mode: AGPU_COPY_DESTINATION_BUFFER;
		usage_modes: AGPU_COPY_DESTINATION_BUFFER;
		mapping_flags: AGPU_MAP_READ_BIT | AGPU_MAP_PERSISTENT_BIT | AGPU_MAP_COHERENT_BIT;
		yourself) initial_data: nil.
		
	leftMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	leftMatrixBinding bindStorageBuffer: 0 storage_buffer: leftMatrixBuffer.
	
	rightMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	rightMatrixBinding bindStorageBuffer: 0 storage_buffer: rightMatrixBuffer.
	
	outputMatrixBinding := shaderSignature createShaderResourceBinding: 0.
	outputMatrixBinding bindStorageBuffer: 0 storage_buffer: outputMatrixBuffer.
	
	commandQueue := device getDefaultCommandQueue.
	commandListAllocator := device createCommandAllocator: AGPU_COMMAND_LIST_TYPE_DIRECT queue: commandQueue.
	commandList := device createCommandList: AGPU_COMMAND_LIST_TYPE_DIRECT allocator: commandListAllocator initial_pipeline_state: nil.
	
	uploadBufferPointer := uploadBuffer mapBuffer: AGPU_WRITE_ONLY.
	readbackBufferPointer := readbackBuffer mapBuffer: AGPU_READ_ONLY.
	
	LibC memCopy: leftMatrix to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { 
		leftMatrixExtent x.
		leftMatrixExtent y.
		rightMatrixExtent x.
		rightMatrixExtent y.
		outputMatrixExtent x.
		outputMatrixExtent y.
	} asWordArray.
	
	commandList
		"Copy from host buffer into the left buffer."
		pushBufferTransitionBarrier: leftMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: 0
			dest_buffer: leftMatrixBuffer dest_offset: 0 copy_size: leftMatrix size * 4;
		popBufferTransitionBarrier;

		"Copy from host buffer into the right buffer."
		pushBufferTransitionBarrier: rightMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_DESTINATION_BUFFER;
		copyBuffer: uploadBuffer source_offset: leftMatrix size * 4
			dest_buffer: rightMatrixBuffer dest_offset: 0 copy_size: rightMatrix size * 4;
		popBufferTransitionBarrier;
	
		setShaderSignature: shaderSignature;
		usePipelineState: computePipeline;
		useComputeShaderResourcesInSlot: leftMatrixBinding slot: 0;
		useComputeShaderResourcesInSlot: rightMatrixBinding slot: 1;
		useComputeShaderResourcesInSlot: outputMatrixBinding slot: 2;
		pushConstants: 0 size: extentsPushConstants size * 4 values: extentsPushConstants;
		dispatchCompute: (outputMatrixExtent x + 7) // 8 group_count_y: (outputMatrixExtent y + 7) // 8 group_count_z: 1;
		
		"Copy from device buffer into the host buffer."
		pushBufferTransitionBarrier: outputMatrixBuffer old_usage: AGPU_STORAGE_BUFFER new_usage: AGPU_COPY_SOURCE_BUFFER;
		copyBuffer: outputMatrixBuffer source_offset: 0
			dest_buffer: readbackBuffer dest_offset: 0 copy_size: outputMatrix size * 4;
		popBufferTransitionBarrier;
		
		close.
		
	commandQueue
		addCommandList: commandList;
		finishExecution.
	
	LibC memCopy: readbackBufferPointer to: outputMatrix size: outputMatrix size * 4.
	"
	leftMatrix inspect
	rightMatrix inspect
	outputMatrix inspect
	"
	(Dictionary newFromPairs: {
		#leftMatrix. leftMatrix . 
		#rightMatrix. rightMatrix. 
		#outputMatrix. outputMatrix } ) inspect
	
]

{ #category : #'see class side' }
AGPUMLSample >> seeClassSide [
]
