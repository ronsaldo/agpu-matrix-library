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

{ #category : #'instance creation' }
AGPUMatMulFP32 class >> uniqueInstance [
	^ uniqueInstance ifNil: [ uniqueInstance := self new ]
]

{ #category : #initialization }
AGPUMatMulFP32 >> initialize [ 	
	self setShader
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
