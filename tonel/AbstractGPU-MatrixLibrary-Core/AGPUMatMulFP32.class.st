"
Please comment me using the following template inspired by Class Responsibility Collaborator (CRC) design:

Class:
I represent a GPU vulkan shader to calculate matrix multiplication for 32-bit floats.

Responsibility: 
I know how to get shader code compiled into the GPU and cache the compiled shader.
I recieve matrices as FloatArrays and pass these to the shader for calculation. 

Collaborators:
- AGPU - #mainDevice provides the GPU that the shader is created/compiled for.
- AGPUMatrix - holds the 2D matrix. Its #@ message invokes me to multiply two matrix. In future want this to be a tensor. 

Public API and Key Messages
- AGPUMatMulFP32 uniqueInstance multiplyLeft: lhsMatrix byRight: rhsMatrix.
 
Internal Representation and Key Implementation Points.

    Instance Variables
	computePipeline:		<Object>
	device:		<Object>
	shaderSignature:		<Object>


    Implementation Points
"
Class {
	#name : #AGPUMatMulFP32,
	#superclass : #Object,
	#instVars : [
		'shaderSignature',
		'computePipeline',
		'device'
	],
	#pools : [
		'AGPUConstants'
	],
	#classInstVars : [
		'uniqueInstance'
	],
	#category : #'AbstractGPU-MatrixLibrary-Core'
}

{ #category : #'class initialization' }
AGPUMatMulFP32 class >> reset [
	^ self uniqueInstance setShader
]

{ #category : #'instance creation' }
AGPUMatMulFP32 class >> uniqueInstance [
	^ uniqueInstance ifNil: [ uniqueInstance := self new ]
]

{ #category : #initialization }
AGPUMatMulFP32 >> initialize [ 	
	self setShader
]

{ #category : #operations }
AGPUMatMulFP32 >> multiplyLeft: leftMatrix byRight: rightMatrix [ 
	| m k n uploadBuffer leftMatrixBuffer rightMatrixBuffer outputMatrix outputMatrixBuffer readbackBuffer leftMatrixBinding rightMatrixBinding outputMatrixBinding commandQueue commandListAllocator commandList uploadBufferPointer readbackBufferPointer extentsPushConstants |

	m := leftMatrix numberOfRows.
	k := leftMatrix numberOfColumns.
	n := rightMatrix numberOfColumns.
	k = rightMatrix numberOfRows ifFalse: [self error: 'dimensions do not conform'].

	outputMatrix := FloatArray new: m * n.
		
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
	
	LibC memCopy: leftMatrix asFloatArray to: uploadBufferPointer size: leftMatrix size * 4.
	LibC memCopy: rightMatrix asFloatArray to: uploadBufferPointer + (leftMatrix size * 4) size: rightMatrix size * 4.
	extentsPushConstants := { m. k. n} asWordArray.
	
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
		dispatchCompute: (m + 7) // 8 group_count_y: (n + 7) // 8 group_count_z: 1;
		
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
	^ AGPUMatrix rows: m columns: n contents: outputMatrix

]

{ #category : #initialization }
AGPUMatMulFP32 >> setShader [
	| shaderSource shader |
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
		
		addBindingConstant; "m"
		addBindingConstant; "k"
		addBindingConstant; "n"

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
	uint m;
	uint k;
	uint n;
} MatricesLayout;

#define leftIndexAt(i, j) ((i)*MatricesLayout.k + (j))
#define leftAt(i, j) LeftInputMatrix.elements[leftIndexAt(i, j)]

#define rightIndexAt(i, j) ((i)*MatricesLayout.n + (j))
#define rightAt(i, j) RightInputMatrix.elements[rightIndexAt(i, j)]

#define outputIndexAt(i, j) ((i)*MatricesLayout.n + (j))
#define outputAt(i, j) OutputMatrix.elements[outputIndexAt(i, j)]

void main()
{
	uint i = gl_GlobalInvocationID.y;
	uint j = gl_GlobalInvocationID.x;	

	uint K = MatricesLayout.k;
	float result = -0.0;
	for(uint k = 0u; k < K; ++k)
		result += leftAt(i, k) * rightAt(k, j);
		
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
]
